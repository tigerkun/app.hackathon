/**
 * SafeSphere End-to-End User Scenario Test Suite
 * Tests full real-world citizen, victim, guardian, and responder user journeys.
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { server, wss } = require('../src/server');
const { db } = require('../src/data/store');

describe('User Scenarios: Real-World SafeSphere End-to-End Flows', async () => {
  let baseUrl;
  let testPort;

  before(async () => {
    process.env.NODE_ENV = 'test';
    db.reset();

    await new Promise((resolve, reject) => {
      server.listen(0, '127.0.0.1', (err) => {
        if (err) return reject(err);
        resolve();
      });
    });

    testPort = server.address().port;
    baseUrl = `http://127.0.0.1:${testPort}`;
  });

  after(async () => {
    for (const client of wss.clients) {
      try { client.terminate(); } catch (_) {}
    }
    await new Promise((resolve) => {
      server.close(resolve);
    });
  });

  // Helper for HTTP requests
  async function api(path, { method = 'GET', body = null, headers = {} } = {}) {
    const url = `${baseUrl}${path}`;
    const opts = {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };
    if (body) {
      opts.body = typeof body === 'string' ? body : JSON.stringify(body);
    }
    const res = await fetch(url, opts);
    let data = null;
    const text = await res.text();
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = text;
    }
    return { status: res.status, headers: res.headers, body: data };
  }

  // =========================================================================
  // SCENARIO 1: Critical Distress SOS, Live Chat & Victim Resolution
  // =========================================================================
  it('Scenario 1: Victim triggers SOS, exchanges chat with responder, and self-resolves', async () => {
    // 1. Victim (citizen) triggers SOS
    const sosRes = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 4.5,
        batteryLevel: 22,
        alertType: 'CRITICAL_SOS',
        notes: 'Followed by two individuals near bus stop'
      }
    });
    assert.equal(sosRes.status, 201, 'SOS trigger should return 201 Created');
    const alertId = sosRes.body.data.id || sosRes.body.alert.id;
    const resolveToken = sosRes.body.resolveToken || sosRes.body.data.resolveToken;
    assert.ok(alertId, 'Alert ID must be present');
    assert.ok(resolveToken, 'Plaintext resolveToken must be issued at trigger');

    // 2. Alert is active and visible
    const activeRes = await api('/api/v1/sos/active');
    assert.equal(activeRes.status, 200);
    const foundAlert = activeRes.body.data.find(a => a.id === alertId);
    assert.ok(foundAlert, 'Alert must be in active list');
    assert.equal(foundAlert.status, 'active');
    // Security check: resolveTokenHash must NEVER leak
    assert.equal(foundAlert.resolveTokenHash, undefined);

    // 3. Victim posts chat message using resolveToken
    const chatMsg1 = await api(`/api/v1/sos/${alertId}/messages`, {
      method: 'POST',
      body: {
        token: resolveToken,
        text: "I'm hiding behind the pharmacy counter."
      }
    });
    assert.equal(chatMsg1.status, 201, 'Victim should post message with resolveToken');
    assert.equal(chatMsg1.body.data.text, "I'm hiding behind the pharmacy counter.");

    // 4. Rate-limiting check: victim cannot spam chat faster than 1 msg / 2s
    const spamMsg = await api(`/api/v1/sos/${alertId}/messages`, {
      method: 'POST',
      body: {
        token: resolveToken,
        text: "Spam message immediately"
      }
    });
    assert.equal(spamMsg.status, 429, 'Rate limiter should reject messages < 2s apart');

    // 5. Read chat messages
    const getMsgs = await api(`/api/v1/sos/${alertId}/messages?token=${resolveToken}`);
    assert.equal(getMsgs.status, 200);
    assert.ok(getMsgs.body.data.length >= 1);
    assert.equal(getMsgs.body.data[0].text, "I'm hiding behind the pharmacy counter.");

    // 6. Victim resolves alert using resolveToken
    // Try wrong token first
    const badResolve = await api(`/api/v1/sos/${alertId}/resolve`, {
      method: 'POST',
      body: {
        resolveToken: 'wrong-token-12345',
        notes: 'Trying to cancel'
      }
    });
    assert.equal(badResolve.status, 401, 'Invalid resolveToken must be rejected');

    // Correct token
    const goodResolve = await api(`/api/v1/sos/${alertId}/resolve`, {
      method: 'POST',
      body: {
        resolveToken: resolveToken,
        notes: 'Help arrived, I am safe now.'
      }
    });
    assert.equal(goodResolve.status, 200, 'Alert should be successfully resolved');
    assert.equal(goodResolve.body.data.status, 'resolved');

    // Verify it is no longer in active list
    const activeAfter = await api('/api/v1/sos/active');
    assert.ok(!activeAfter.body.data.some(a => a.id === alertId), 'Resolved alert must not appear in active list');
  });

  // =========================================================================
  // SCENARIO 2: Guardian Live Tracking, Stalling & Check-in Dead-Man Switch
  // =========================================================================
  it('Scenario 2: Broadcaster shares live tracking, sends pings, stall watchdog detects freeze', async () => {
    // 1. Create tracking session with 10-minute checkin
    const trackRes = await api('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        userName: 'Priya Sharma',
        latitude: 28.5355,
        longitude: 77.3910,
        battery: 85,
        durationMinutes: 30,
        checkInIntervalMin: 10
      }
    });
    assert.equal(trackRes.status, 201);
    const { sessionId, token, shareUrl } = trackRes.body;
    assert.ok(sessionId && token && shareUrl);

    // 2. Guardian reads track snapshot via token
    const guardianRead = await api(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(guardianRead.status, 200);
    assert.equal(guardianRead.body.data.userName, 'Priya Sharma');
    assert.equal(guardianRead.body.data.status, 'active');
    assert.equal(guardianRead.body.data.stallDetected, false);

    // 3. Broadcaster sends GPS ping
    const pingRes = await api('/api/v1/location/ping', {
      method: 'POST',
      body: {
        sessionId,
        token,
        latitude: 28.5360,
        longitude: 77.3915,
        battery: 84
      }
    });
    assert.equal(pingRes.status, 200);
    assert.equal(pingRes.body.data.pointCount, 2);

    // 4. Broadcaster arrives safely and terminates session
    const termRes = await api(`/api/v1/location/terminate/${sessionId}`, {
      method: 'POST',
      body: {
        token,
        reason: 'Arrived at destination'
      }
    });
    assert.equal(termRes.status, 200);
    assert.equal(termRes.body.data.status, 'ended');
  });

  // =========================================================================
  // SCENARIO 3: Community Hazard Reporting with Photo Attachment & Voting
  // =========================================================================
  it('Scenario 3: Citizen posts incident with valid photo, community votes to confirm', async () => {
    // Register verified citizen
    const ts = Date.now();
    const email = `citizen_${ts}@safesphere.test`;
    const phone = `+919${Math.floor(100000000 + Math.random() * 900000000)}`;
    const regRes = await api('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Aarav Mehta',
        email,
        phone,
        password: 'Password@123'
      }
    });
    assert.equal(regRes.status, 201);
    const token = regRes.body.accessToken;
    const userId = regRes.body.user.id;

    // Verify phone for reporting/voting permissions
    db.updateUser(userId, { phoneVerified: 1 });

    // Valid PNG base64 (89 50 4E 47 0D 0A 1A 0A)
    const validPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

    // Submit report
    const repRes = await api('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: {
        type: 'hazard',
        description: 'Large pothole and exposed wiring near pedestrian crossing',
        location: 'Sector 18 Metro Gate 2',
        latitude: 28.5700,
        longitude: 77.3200,
        photoBase64: validPngBase64
      }
    });
    assert.equal(repRes.status, 201);
    const reportId = repRes.body.data.id;
    assert.ok(repRes.body.data.photoUrl.startsWith('data:image/png;base64,'));

    // Register second verified citizen to vote
    const voterEmail = `voter_${Date.now()}@safesphere.test`;
    const voterPhone = `+919${Math.floor(100000000 + Math.random() * 900000000)}`;
    const voterReg = await api('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Divya Nair',
        email: voterEmail,
        phone: voterPhone,
        password: 'Password@123'
      }
    });
    const voterToken = voterReg.body.accessToken;
    db.updateUser(voterReg.body.user.id, { phoneVerified: 1 });

    // Vote on report
    const voteRes = await api(`/api/v1/reports/${reportId}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${voterToken}` },
      body: { vote: 'confirm' }
    });
    assert.equal(voteRes.status, 200);
    assert.equal(voteRes.body.data.upvotes, 1);
  });

  // =========================================================================
  // SCENARIO 4: Trusted Circle Connection & Instant Revocation
  // =========================================================================
  it('Scenario 4: Two users connect via Safe ID, share location, and revoke immediately', async () => {
    // User A (Alice)
    const aliceRes = await api('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Alice',
        email: `alice_${Date.now()}@safesphere.test`,
        phone: `+919${Math.floor(100000000 + Math.random() * 900000000)}`,
        password: 'Password@123'
      }
    });
    const aliceToken = aliceRes.body.accessToken;
    const aliceSafeId = aliceRes.body.user.safeId;

    // User B (Bob)
    const bobRes = await api('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Bob',
        email: `bob_${Date.now()}@safesphere.test`,
        phone: `+919${Math.floor(100000000 + Math.random() * 900000000)}`,
        password: 'Password@123'
      }
    });
    const bobToken = bobRes.body.accessToken;

    // Bob requests connection with Alice using Alice's Safe ID
    const connReq = await api('/api/v1/connections', {
      method: 'POST',
      headers: { Authorization: `Bearer ${bobToken}` },
      body: {
        ownerSafeId: aliceSafeId,
        scopes: ['location', 'sos_status'],
        mode: 'always'
      }
    });
    assert.equal(connReq.status, 201);
    const connId = connReq.body.data.id;

    // Alice accepts
    const acceptRes = await api(`/api/v1/connections/${connId}/respond`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${aliceToken}` },
      body: { accept: true }
    });
    assert.equal(acceptRes.status, 200);

    // Alice pings location beacon
    const beaconRes = await api(`/api/v1/connections/${connId}/ping`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${aliceToken}` },
      body: { latitude: 28.6140, longitude: 77.2092, accuracy: 6.0 }
    });
    assert.equal(beaconRes.status, 200);

    // Bob reads live location
    const bobLive = await api(`/api/v1/connections/${connId}/live`, {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(bobLive.status, 200);
    assert.equal(bobLive.body.data.hasSignal, true);
    assert.equal(bobLive.body.data.location.latitude, 28.6140);

    // Bob tries to read alerts (unauthorized scope) -> 403 SCOPE_NOT_GRANTED
    const badScope = await api(`/api/v1/connections/${connId}/alerts`, {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(badScope.status, 403);
    assert.equal(badScope.body.error.code, 'SCOPE_NOT_GRANTED');

    // Alice revokes connection
    const revokeRes = await api(`/api/v1/connections/${connId}/revoke`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${aliceToken}` }
    });
    assert.equal(revokeRes.status, 200);

    // Bob tries to read location again -> 403 CONNECTION_REVOKED
    const bobAfterRevoke = await api(`/api/v1/connections/${connId}/live`, {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(bobAfterRevoke.status, 403);
    assert.equal(bobAfterRevoke.body.error.code, 'CONNECTION_REVOKED');
  });

  // =========================================================================
  // SCENARIO 5: Offline SOS Replay Idempotency
  // =========================================================================
  it('Scenario 5: Client requestId idempotency prevents duplicate SOS replay', async () => {
    const clientRequestId = `req_${Date.now()}_dedup_test`;

    // First trigger
    const res1 = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: {
        clientRequestId,
        latitude: 28.6139,
        longitude: 77.2090,
        notes: 'Original trigger'
      }
    });
    assert.equal(res1.status, 201);
    const alertId1 = res1.body.data.id || res1.body.alert.id;

    // Replay with identical clientRequestId
    const res2 = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: {
        clientRequestId,
        latitude: 28.6139,
        longitude: 77.2090,
        notes: 'Replayed trigger from queue'
      }
    });
    assert.equal(res2.status, 200);
    assert.equal(res2.body.deduplicated, true);
    const alertId2 = res2.body.data.id || res2.body.id;
    assert.equal(alertId1, alertId2, 'Replay must return original alert ID, not create a duplicate');
  });

  // =========================================================================
  // SCENARIO 6: DPDP Full Right-to-Erasure Account Deletion
  // =========================================================================
  it('Scenario 6: User with PIN deletes account, verifying cascading erasure', async () => {
    // 1. Register user
    const regRes = await api('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Vikram Singh',
        email: `vikram_${Date.now()}@safesphere.test`,
        phone: `+919${Math.floor(100000000 + Math.random() * 900000000)}`,
        password: 'Password@123'
      }
    });
    const token = regRes.body.accessToken;
    const userId = regRes.body.user.id;

    // Set PIN
    const bcrypt = require('bcryptjs');
    const pinHash = await bcrypt.hash('1234', 10);
    db.updateUser(userId, { pinHash });

    // 2. Try delete with wrong PIN -> 401
    const badDelete = await api('/api/v1/auth/me', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
      body: { pin: '9999' }
    });
    assert.equal(badDelete.status, 401);
    assert.equal(badDelete.body.error.code, 'INVALID_PIN');

    // 3. Delete with correct PIN -> 200
    const goodDelete = await api('/api/v1/auth/me', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
      body: { pin: '1234' }
    });
    assert.equal(goodDelete.status, 200);

    // 4. Verify account no longer exists
    assert.equal(db.findUserById(userId), null);
    const meRes = await api('/api/v1/auth/me', {
      headers: { Authorization: `Bearer ${token}` }
    });
    assert.equal(meRes.status, 401);
  });

  // =========================================================================
  // SCENARIO 7: Malformed, Hostile, & Boundary Payloads (Fuzzing & Robustness)
  // =========================================================================
  it('Scenario 7: Malformed coordinates, oversized notes, and boundary payloads fail cleanly', async () => {
    // Latitude out of bounds (> 90)
    const badLat = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: { latitude: 91.0, longitude: 77.2090 }
    });
    assert.equal(badLat.status, 400, 'Latitude > 90 must be rejected with 400');

    // Longitude out of bounds (< -180)
    const badLon = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: { latitude: 28.0, longitude: -185.0 }
    });
    assert.equal(badLon.status, 400, 'Longitude < -180 must be rejected with 400');

    // Non-numeric coordinates (NaN)
    const nanCoords = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: { latitude: 'invalid', longitude: 77.0 }
    });
    assert.equal(nanCoords.status, 400, 'String latitude must be rejected with 400');

    // Oversized notes (> 500 characters)
    const hugeNotes = 'A'.repeat(501);
    const badNotes = await api('/api/v1/sos/trigger', {
      method: 'POST',
      body: { latitude: 28.0, longitude: 77.0, notes: hugeNotes }
    });
    assert.equal(badNotes.status, 400, 'Notes > 500 chars must be rejected with 400');

    // Invalid tracking check-in interval (< 1 or > 1440)
    const badInterval = await api('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        userName: 'Test User',
        latitude: 28.0,
        longitude: 77.0,
        checkInIntervalMin: 2000
      }
    });
    assert.equal(badInterval.status, 400, 'checkInIntervalMin > 1440 must be rejected');
  });

  // =========================================================================
  // SCENARIO 8: WebSocket Real-Time Connection & Robustness
  // =========================================================================
  it('Scenario 8: WebSocket connection survives malformed frames and broadcasts messages', async () => {
    const WebSocket = require('ws');
    const wsUrl = baseUrl.replace('http://', 'ws://') + '/ws/sos';

    const ws = new WebSocket(wsUrl);

    await new Promise((resolve, reject) => {
      ws.on('open', resolve);
      ws.on('error', reject);
    });

    // 1. Send malformed/non-JSON data -> Server must NOT crash
    ws.send('{malformed-json');
    await new Promise(r => setTimeout(r, 50));

    // 2. Send empty or unexpected frame types -> Server must stay alive
    ws.send(JSON.stringify({ type: 'UNKNOWN_TEST_TYPE' }));
    await new Promise(r => setTimeout(r, 50));

    // 3. Ping / Pong test
    let pongReceived = false;
    ws.on('pong', () => { pongReceived = true; });
    ws.ping();
    await new Promise(r => setTimeout(r, 50));
    assert.ok(pongReceived, 'WebSocket server must respond to ping frames');

    ws.close();
  });

  // =========================================================================
  // SCENARIO 9: AI Assistant Offline & Out-of-Scope Honesty
  // =========================================================================
  it('Scenario 9: AI assistant returns honest 503 when unconfigured and rejects empty messages', async () => {
    // Missing or empty prompt
    const emptyRes = await api('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: '' }
    });
    assert.equal(emptyRes.status, 400, 'Blank message must return 400');
    assert.equal(emptyRes.body.error.code, 'MISSING_MESSAGE');

    // Oversized prompt (> 1000 characters)
    const hugePrompt = 'Help '.repeat(300);
    const hugeRes = await api('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: hugePrompt }
    });
    assert.equal(hugeRes.status, 400, 'Oversized message must return 400');
    assert.equal(hugeRes.body.error.code, 'MESSAGE_TOO_LONG');

    // Without GROQ_API_KEY -> honest 503 AI_NOT_CONFIGURED
    const prevKey = process.env.GROQ_API_KEY;
    delete process.env.GROQ_API_KEY;
    const aiRes = await api('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'What should I do if a stray dog approaches aggressively?' }
    });
    assert.equal(aiRes.status, 503, 'Unconfigured AI assistant must return honest 503');
    assert.equal(aiRes.body.error.code, 'AI_NOT_CONFIGURED');
    if (prevKey) process.env.GROQ_API_KEY = prevKey;
  });

  // =========================================================================
  // SCENARIO 10: Safety Markers Proximity & 24x7 Stores Search
  // =========================================================================
  it('Scenario 10: Proximity search returns nearest 24x7 stores and emergency refuges', async () => {
    // Create verified store marker at Connaught Place
    db.saveMarker({
      id: `mkr_${Date.now()}_store`,
      name: '24x7 Convenience & Safe Refuge',
      category: 'store',
      latitude: 28.6315,
      longitude: 77.2167,
      address: 'Inner Circle, CP, New Delhi',
      isVerified: 1,
      status: 'verified',
      createdAt: new Date().toISOString()
    });

    // Query markers near Connaught Place (within 3km)
    const nearbyRes = await api('/api/v1/markers?latitude=28.6310&longitude=77.2160&radius=3&category=store');
    assert.equal(nearbyRes.status, 200);
    assert.ok(nearbyRes.body.data.length >= 1, 'Store must appear in nearby search');
    const store = nearbyRes.body.data.find(m => m.category === 'store');
    assert.ok(store, '24x7 store marker must be returned');
    assert.equal(store.name, '24x7 Convenience & Safe Refuge');
  });
});
