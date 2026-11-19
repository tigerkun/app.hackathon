/**
 * SafeSphere Wave 2 Enhancements Test Suite
 * Verifies:
 * - W2-1: Browser-accessible guardian tracker on GET /?session=...&token=... and /track
 * - W2-2: Hyperlocal community reports filtering by lat/lng/radiusKm (capped at 50km)
 * - W2-3: GET /api/v1/sos/mine behind requireAuth and monitorsConnected in active/getById
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');
const { signAccessToken } = require('../src/services/tokenService');

describe('SafeSphere Wave 2 User-Facing Enhancements', () => {
  let serverHarness;
  let baseUrl;
  let testUserToken;
  let testUserId;
  let otherUserToken;
  let otherUserId;

  before(async () => {
    serverHarness = await startTestServer();
    baseUrl = serverHarness.baseUrl;

    // Seed test users
    const user1 = db.saveUser(createUser({
      name: 'Wave2 User One',
      email: 'wave2_user1@safesphere.test',
      phone: '+919999900001',
      passwordHash: 'dummy',
      role: 'citizen'
    }));
    testUserId = user1.id;
    testUserToken = signAccessToken(user1, 'sess_1');

    const user2 = db.saveUser(createUser({
      name: 'Wave2 User Two',
      email: 'wave2_user2@safesphere.test',
      phone: '+919999900002',
      passwordHash: 'dummy',
      role: 'citizen'
    }));
    otherUserId = user2.id;
    otherUserToken = signAccessToken(user2, 'sess_2');
  });

  after(async () => {
    if (serverHarness) {
      await serverHarness.close();
    }
  });

  // ===========================================================================
  // W2-1: Browser-Accessible Guardian Tracker
  // ===========================================================================
  describe('W2-1: Browser-Accessible Guardian Tracker (GET /?session=...&token=... & /track)', () => {
    it('returns text/html 200 on GET /?session=trk_test&token=tok_test with security headers', async () => {
      const res = await fetch(`${baseUrl}/?session=trk_test&token=tok_test`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'), 'HTML title missing');
      assert.ok(body.includes('#0B0F1A'), 'Dark background color missing');
      assert.ok(body.includes('textContent'), 'Script must use textContent for XSS safety');
      assert.ok(!body.includes('innerHTML'), 'Script must NOT use innerHTML');
    });

    it('returns text/html 200 on GET /?sessionId=trk_test&token=tok_test', async () => {
      const res = await fetch(`${baseUrl}/?sessionId=trk_test&token=tok_test`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'));
    });

    it('returns text/html 200 on GET /track with security headers and handles empty params', async () => {
      const res = await fetch(`${baseUrl}/track`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'));
      assert.ok(body.includes('AWAITING SESSION'), 'Tracker shell handles empty params in awaiting state');
      assert.ok(!body.includes('stack'), 'Tracker HTML response must not leak stack traces');
    });

    it('returns 200 HTML shell with awaiting state on GET /?session=x (no token) without crashing or leaking stack traces', async () => {
      const res = await fetch(`${baseUrl}/?session=trk_notoken_test`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      assert.equal(res.headers.get('cache-control'), 'no-store');
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'));
      assert.ok(body.includes('AWAITING SESSION'), 'Tracker shell renders awaiting state');
      assert.ok(!body.includes('stack'), 'Tracker HTML response must not leak stack traces');
    });

    it('verifies tracker negative paths: API rejects missing or invalid tracking token without leaking stack traces', async () => {
      // Seed a tracking session first so we test token assertion on an existing session
      const createRes = await serverHarness.request('/api/v1/location/share-session', {
        method: 'POST',
        headers: { Authorization: `Bearer ${testUserToken}` },
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      assert.equal(createRes.status, 201);
      const sessId = createRes.body.data.sessionId;

      // 1. Missing token on existing session -> 401 MISSING_TRACKING_TOKEN
      const missingTokenRes = await serverHarness.request(`/api/v1/location/track/${sessId}`);
      assert.equal(missingTokenRes.status, 401);
      assert.equal(missingTokenRes.body.error.code, 'MISSING_TRACKING_TOKEN');
      assert.equal(missingTokenRes.body.error.stack, undefined, 'No stack trace in 401 response');

      // 2. Invalid token on existing session -> 401 INVALID_TRACKING_TOKEN
      const invalidTokenRes = await serverHarness.request(`/api/v1/location/track/${sessId}?token=invalid_tok`);
      assert.equal(invalidTokenRes.status, 401);
      assert.equal(invalidTokenRes.body.error.code, 'INVALID_TRACKING_TOKEN');
      assert.equal(invalidTokenRes.body.error.stack, undefined, 'No stack trace in 401 response');

      // 3. Non-existent session -> 404
      const nonExistentRes = await serverHarness.request('/api/v1/location/track/trk_nonexistent?token=tok_test');
      assert.equal(nonExistentRes.status, 404);
      assert.equal(nonExistentRes.body.error.code, 'SESSION_NOT_FOUND');
      assert.equal(nonExistentRes.body.error.stack, undefined, 'No stack trace in 404 response');
    });

    it('preserves standard JSON 200 response on bare GET / when no session or token query params are present', async () => {
      const res = await fetch(`${baseUrl}/`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('application/json'), `Expected application/json, got ${contentType}`);
      const body = await res.json();
      assert.equal(body.name, 'SafeSphere API Service');
      assert.equal(body.status, 'operational');
    });

    it('leaves /health, /healthz, and /api/v1 unaffected', async () => {
      const healthRes = await fetch(`${baseUrl}/health`);
      assert.equal(healthRes.status, 200);
      const healthBody = await healthRes.json();
      assert.equal(healthBody.status, 'healthy');

      const healthzRes = await fetch(`${baseUrl}/healthz`);
      assert.equal(healthzRes.status, 200);
      const healthzBody = await healthzRes.json();
      assert.equal(healthzBody.status, 'ok');

      const apiRes = await fetch(`${baseUrl}/api/v1`);
      assert.equal(apiRes.status, 200);
      const apiBody = await apiRes.json();
      assert.equal(apiBody.status, 'ok');
    });
  });

  // ===========================================================================
  // W2-2: Hyperlocal Community Data Filtering
  // ===========================================================================
  describe('W2-2: Hyperlocal Community Reports (GET /api/v1/reports)', () => {
    before(() => {
      // Seed reports at specific coordinates
      // Connaught Place, New Delhi (~28.6315, 77.2167)
      db.saveReport({
        id: 'rep_cp_01',
        type: 'theft',
        description: 'Bicycle stolen near Inner Circle CP',
        location: 'Connaught Place',
        latitude: 28.6315,
        longitude: 77.2167,
        status: 'verified',
        reportedBy: testUserId,
        createdAt: new Date().toISOString()
      });

      // Karol Bagh, New Delhi (~3.5km from CP: 28.6517, 77.1906)
      db.saveReport({
        id: 'rep_kb_01',
        type: 'hazard',
        description: 'Open manhole on Arya Samaj Road',
        location: 'Karol Bagh',
        latitude: 28.6517,
        longitude: 77.1906,
        status: 'verified',
        reportedBy: testUserId,
        createdAt: new Date().toISOString()
      });

      // Noida Sector 62 (~17km from CP: 28.6258, 77.3644)
      db.saveReport({
        id: 'rep_noida_01',
        type: 'accident',
        description: 'Minor collision near Sector 62 metro',
        location: 'Noida Sector 62',
        latitude: 28.6258,
        longitude: 77.3644,
        status: 'verified',
        reportedBy: otherUserId,
        createdAt: new Date().toISOString()
      });

      // Bengaluru (~1700km away: 12.9716, 77.5946)
      db.saveReport({
        id: 'rep_blr_01',
        type: 'harassment',
        description: 'Incident near MG Road metro',
        location: 'Bengaluru MG Road',
        latitude: 12.9716,
        longitude: 77.5946,
        status: 'verified',
        reportedBy: otherUserId,
        createdAt: new Date().toISOString()
      });
    });

    it('returns all reports without proximity filtering when lat/lng are omitted', async () => {
      const res = await serverHarness.request('/api/v1/reports');
      assert.equal(res.status, 200);
      assert.ok(res.body.count >= 4);
    });

    it('filters reports within default 10km radius of Connaught Place (includes CP and Karol Bagh, excludes Noida and BLR)', async () => {
      const res = await serverHarness.request('/api/v1/reports?lat=28.6315&lng=77.2167&radiusKm=10');
      assert.equal(res.status, 200);
      assert.ok(res.body.data.length >= 2, 'Expected at least CP and Karol Bagh');
      const ids = res.body.data.map(r => r.id);
      assert.ok(ids.includes('rep_cp_01'), 'Must include CP report');
      assert.ok(ids.includes('rep_kb_01'), 'Must include Karol Bagh report');
      assert.ok(!ids.includes('rep_noida_01'), 'Must NOT include Noida (17km away)');
      assert.ok(!ids.includes('rep_blr_01'), 'Must NOT include Bengaluru (1700km away)');
    });

    it('includes farther reports (Noida) when radius is expanded to 25km', async () => {
      const res = await serverHarness.request('/api/v1/reports?latitude=28.6315&longitude=77.2167&radiusKm=25');
      assert.equal(res.status, 200);
      const ids = res.body.data.map(r => r.id);
      assert.ok(ids.includes('rep_cp_01'));
      assert.ok(ids.includes('rep_kb_01'));
      assert.ok(ids.includes('rep_noida_01'), 'Noida must be included within 25km');
      assert.ok(!ids.includes('rep_blr_01'), 'Bengaluru still excluded');
    });

    it('caps radius at 50km even when client requests radiusKm=5000', async () => {
      const res = await serverHarness.request('/api/v1/reports?lat=28.6315&lng=77.2167&radiusKm=5000');
      assert.equal(res.status, 200);
      const ids = res.body.data.map(r => r.id);
      // Because radius is capped at 50km, Bengaluru (~1700km away) must NOT be returned!
      assert.ok(!ids.includes('rep_blr_01'), 'Bengaluru must NOT be returned when radius is capped at 50km');
    });

    it('clamps radius to minimum 1km when radiusKm <= 0 or fractional (e.g. radiusKm=0.1, radiusKm=0)', async () => {
      // With radius clamped to 1km, only CP report (dist 0km) is returned; Karol Bagh (~4km) is excluded
      const resFractional = await serverHarness.request('/api/v1/reports?lat=28.6315&lng=77.2167&radiusKm=0.1');
      assert.equal(resFractional.status, 200);
      const idsFractional = resFractional.body.data.map(r => r.id);
      assert.ok(idsFractional.includes('rep_cp_01'), 'Must include immediate CP report within 1km');
      assert.ok(!idsFractional.includes('rep_kb_01'), 'Must exclude Karol Bagh (~4km away)');

      // Same clamp for zero radius
      const resZero = await serverHarness.request('/api/v1/reports?lat=28.6315&lng=77.2167&radiusKm=0');
      assert.equal(resZero.status, 200);
      const idsZero = resZero.body.data.map(r => r.id);
      assert.ok(idsZero.includes('rep_cp_01'));
      assert.ok(!idsZero.includes('rep_kb_01'));
    });

    it('returns empty list when user is in location with zero nearby reports', async () => {
      // Point in middle of the ocean (0, 0)
      const res = await serverHarness.request('/api/v1/reports?lat=0.0&lng=0.0&radiusKm=10');
      assert.equal(res.status, 200);
      assert.equal(res.body.count, 0);
      assert.deepEqual(res.body.data, []);
    });
  });

  // ===========================================================================
  // W2-3: SOS History & Monitors Status
  // ===========================================================================
  describe('W2-3: SOS Status & History (GET /api/v1/sos/mine & monitorsConnected)', () => {
    let alert1Id;
    let alert2Id;

    before(async () => {
      // Trigger SOS from testUser
      const triggerRes1 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${testUserToken}` },
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      alert1Id = triggerRes1.body.data.id;

      // Trigger SOS from otherUser
      const triggerRes2 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${otherUserToken}` },
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'MEDICAL_EMERGENCY' }
      });
      alert2Id = triggerRes2.body.data.id;
    });

    it('rejects GET /api/v1/sos/mine without authentication with 401 Unauthorized', async () => {
      const res = await serverHarness.request('/api/v1/sos/mine');
      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'UNAUTHORIZED');
    });

    it('returns only own SOS alerts on GET /api/v1/sos/mine when authenticated', async () => {
      const res = await serverHarness.request('/api/v1/sos/mine', {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(res.status, 200);
      assert.ok(res.body.success);
      assert.ok(Array.isArray(res.body.data));
      for (const alert of res.body.data) {
        assert.equal(alert.userId, testUserId, 'All returned alerts must belong to the caller');
      }
      const ids = res.body.data.map(a => a.id);
      assert.ok(ids.includes(alert1Id), 'Must include testUser alert');
      assert.ok(!ids.includes(alert2Id), 'Must NOT include otherUser alert');
    });

    it('filters own alerts by status query on GET /api/v1/sos/mine', async () => {
      const resActive = await serverHarness.request('/api/v1/sos/mine?status=active', {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(resActive.status, 200);
      assert.ok(resActive.body.data.some(a => a.id === alert1Id));

      const resResolved = await serverHarness.request('/api/v1/sos/mine?status=resolved', {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(resResolved.status, 200);
      assert.ok(!resResolved.body.data.some(a => a.id === alert1Id));
    });

    it('returns monitorsConnected count in GET /api/v1/sos/active', async () => {
      const res = await serverHarness.request('/api/v1/sos/active');
      assert.equal(res.status, 200);
      assert.ok('monitorsConnected' in res.body);
      assert.equal(typeof res.body.monitorsConnected, 'number');
    });

    it('returns monitorsConnected count in GET /api/v1/sos/:id', async () => {
      const res = await serverHarness.request(`/api/v1/sos/${alert1Id}`, {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(res.status, 200);
      assert.ok('monitorsConnected' in res.body);
      assert.equal(typeof res.body.monitorsConnected, 'number');
      assert.equal(res.body.data.id, alert1Id);
    });

    it('BUG 8: resolveTokenHash is never exposed in any GET response (active, getById, mine)', async () => {
      // 1. Check GET /api/v1/sos/active
      const activeRes = await serverHarness.request('/api/v1/sos/active');
      assert.equal(activeRes.status, 200);
      for (const a of activeRes.body.data) {
        assert.equal(a.resolveTokenHash, undefined, 'active alert must not contain resolveTokenHash');
      }

      // 2. Check GET /api/v1/sos/:id
      const idRes = await serverHarness.request(`/api/v1/sos/${alert1Id}`, {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(idRes.status, 200);
      assert.equal(idRes.body.data.resolveTokenHash, undefined, 'getById must not contain resolveTokenHash');

      // 3. Check GET /api/v1/sos/mine
      const mineRes = await serverHarness.request('/api/v1/sos/mine', {
        headers: { Authorization: `Bearer ${testUserToken}` }
      });
      assert.equal(mineRes.status, 200);
      for (const a of mineRes.body.data) {
        assert.equal(a.resolveTokenHash, undefined, 'mine alert must not contain resolveTokenHash');
      }
    });

    it('BUG 8: anonymous alert + valid resolveToken + authenticated citizen caller can resolve', async () => {
      // Trigger anonymous alert
      const anonTrigger = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      assert.equal(anonTrigger.status, 201);
      const anonAlertId = anonTrigger.body.data?.id || anonTrigger.body.id;
      const anonResolveToken = anonTrigger.body.data?.resolveToken || anonTrigger.body.resolveToken;
      assert.ok(anonAlertId, 'Anonymous trigger returns alert ID');
      assert.ok(anonResolveToken, 'Anonymous trigger returns resolveToken');
      assert.equal(anonTrigger.body.data.resolveTokenHash, undefined, 'Trigger response must not leak hash');
      assert.equal(anonTrigger.body.resolveTokenHash, undefined, 'Trigger response root must not leak hash');

      // Resolve with authenticated citizen account using the resolveToken
      const resolveRes = await serverHarness.request(`/api/v1/sos/${anonAlertId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${testUserToken}` },
        body: { resolveToken: anonResolveToken, notes: 'Citizen self-resolved' }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');
      assert.equal(resolveRes.body.data.resolveTokenHash, undefined, 'Resolve response data must not leak resolveTokenHash');
    });

    it('BUG 8: legacy alert with null resolveTokenHash fails closed for token-bearer but succeeds for admin and responder', async () => {
      const { createAlert } = require('../src/models/alertModel');
      // Create alert with null resolveTokenHash
      const legacyAlert = db.saveAlert(createAlert({
        userId: 'anonymous',
        userName: 'Legacy Victim',
        latitude: 28.61,
        longitude: 77.20,
        resolveTokenHash: null
      }));

      // 1. Unauthenticated resolving with a token fails closed (401)
      const tokenResolve = await serverHarness.request(`/api/v1/sos/${legacyAlert.id}/resolve`, {
        method: 'POST',
        body: { resolveToken: 'any_random_token', notes: 'Should fail' }
      });
      assert.equal(tokenResolve.status, 401);
      assert.equal(tokenResolve.body.error.code, 'UNAUTHORIZED_RESOLVE');

      // 2. Authenticated citizen resolving with a token also fails closed (403)
      const citizenTokenResolve = await serverHarness.request(`/api/v1/sos/${legacyAlert.id}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${testUserToken}` },
        body: { resolveToken: 'any_random_token', notes: 'Should fail' }
      });
      assert.equal(citizenTokenResolve.status, 403);
      assert.equal(citizenTokenResolve.body.error.code, 'FORBIDDEN_RESOLVE');

      // 3. Resolving with a first_responder account succeeds
      const responderUser = db.saveUser({
        id: 'usr_responder_test',
        name: 'Responder Tester',
        email: 'responder_legacy@safesphere.test',
        role: 'first_responder'
      });
      const responderToken = signAccessToken(responderUser, 'sess_responder');
      const responderResolve = await serverHarness.request(`/api/v1/sos/${legacyAlert.id}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${responderToken}` },
        body: { notes: 'Resolved by first responder' }
      });
      assert.equal(responderResolve.status, 200);
      assert.equal(responderResolve.body.data.status, 'resolved');
      assert.equal(responderResolve.body.data.resolveTokenHash, undefined, 'Must not leak resolveTokenHash');

      // 4. Resolving with an admin account succeeds
      const adminUser = db.saveUser({
        id: 'usr_admin_test',
        name: 'Admin Tester',
        email: 'admin_legacy@safesphere.test',
        role: 'admin'
      });
      const adminToken = signAccessToken(adminUser, 'sess_admin');
      const adminResolve = await serverHarness.request(`/api/v1/sos/${legacyAlert.id}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${adminToken}` },
        body: { notes: 'Resolved by admin' }
      });
      assert.equal(adminResolve.status, 200);
      assert.equal(adminResolve.body.data.status, 'resolved');
      assert.equal(adminResolve.body.data.resolveTokenHash, undefined, 'Must not leak resolveTokenHash');
    });
  });

  // ===========================================================================
  // W2-4: Hardening: WS Breadcrumb Persistence & Coordinate Boundary Validation
  // ===========================================================================
  describe('W2-4: Hardening: WS Breadcrumb Persistence & Coordinate Boundary Validation', () => {
    let liveWsServer;
    let wsPort;
    let wsUrl;

    before(async () => {
      const { server } = require('../src/server');
      liveWsServer = server;
      await new Promise((resolve) => {
        if (liveWsServer.listening) {
          wsPort = liveWsServer.address().port;
          wsUrl = `ws://127.0.0.1:${wsPort}/ws/sos`;
          return resolve();
        }
        liveWsServer.listen(0, '127.0.0.1', () => {
          wsPort = liveWsServer.address().port;
          wsUrl = `ws://127.0.0.1:${wsPort}/ws/sos`;
          resolve();
        });
      });
    });

    after(async () => {
      if (liveWsServer && liveWsServer.listening) {
        await new Promise((resolve) => liveWsServer.close(resolve));
      }
    });

    it('persists WebSocket LOCATION_STREAM_UPDATE breadcrumbs to SQLite when valid token is provided', async () => {
      const { WebSocket } = require('ws');
      const { createShareSession } = require('../src/services/trackingService');

      // Create a tracking session in DB
      const share = createShareSession({
        userName: 'WS Breadcrumb User',
        latitude: 28.6139,
        longitude: 77.2090
      });
      const { sessionId, token } = share;

      const ws = new WebSocket(wsUrl);
      await new Promise((resolve) => ws.once('message', resolve)); // welcome message

      // Send LOCATION_STREAM_UPDATE with session token
      ws.send(JSON.stringify({
        type: 'LOCATION_STREAM_UPDATE',
        sessionId,
        token,
        latitude: 28.6145,
        longitude: 77.2095,
        speed: 2.1,
        battery: 92,
        accuracy: 3.5,
        timestamp: new Date().toISOString()
      }));

      // Allow event loop to process DB write
      await new Promise((resolve) => setTimeout(resolve, 80));

      const sessionAfter = db.findTrackingSessionById(sessionId);
      assert.ok(sessionAfter.breadcrumbs.length >= 2, 'Breadcrumb must be saved to DB from WebSocket update');
      const latestCrumb = sessionAfter.breadcrumbs[sessionAfter.breadcrumbs.length - 1];
      assert.equal(latestCrumb.latitude, 28.6145);
      assert.equal(latestCrumb.longitude, 77.2095);
      assert.equal(sessionAfter.currentLocation.latitude, 28.6145);

      ws.close();
    });

    it('enforces FIFO cap of 500 breadcrumbs per tracking session', async () => {
      const { createShareSession, recordPing } = require('../src/services/trackingService');
      const share = createShareSession({
        userName: 'FIFO Cap Tester',
        latitude: 28.6139,
        longitude: 77.2090
      });
      const { sessionId, token } = share;

      // Seed 505 pings
      for (let i = 0; i < 505; i++) {
        recordPing({
          sessionId,
          latitude: 28.0 + (i * 0.0001),
          longitude: 77.0 + (i * 0.0001),
          token
        });
      }

      const session = db.findTrackingSessionById(sessionId);
      assert.equal(session.breadcrumbs.length, 500, 'Breadcrumbs must be capped at 500 entries');
      // Oldest points should have been dropped: first point must not be index 0
      assert.ok(session.breadcrumbs[0].latitude > 28.0004, 'Oldest breadcrumbs must be discarded FIFO');
    });

    it('rejects SOS trigger with invalid or non-finite coordinates', async () => {
      // 1. Latitude > 90
      const res1 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 95.0, longitude: 77.2090 }
      });
      assert.equal(res1.status, 400);
      assert.ok(res1.body.error.details.some(d => d.field === 'latitude'));

      // 2. Latitude < -90
      const res2 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: -91.0, longitude: 77.2090 }
      });
      assert.equal(res2.status, 400);
      assert.ok(res2.body.error.details.some(d => d.field === 'latitude'));

      // 3. Longitude > 180
      const res3 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 185.0 }
      });
      assert.equal(res3.status, 400);
      assert.ok(res3.body.error.details.some(d => d.field === 'longitude'));

      // 4. Longitude < -180
      const res4 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: -185.0 }
      });
      assert.equal(res4.status, 400);
      assert.ok(res4.body.error.details.some(d => d.field === 'longitude'));

      // 5. Non-finite / missing coordinates
      const res5 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 'invalid_lat', longitude: 77.2090 }
      });
      assert.equal(res5.status, 400);
      assert.ok(res5.body.error.details.some(d => d.field === 'latitude'));

      // 6. Valid boundary coordinates are accepted
      const res6 = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 90.0, longitude: 180.0, alertType: 'CRITICAL_SOS' }
      });
      assert.equal(res6.status, 201);
      assert.equal(res6.body.success, true);
    });

    it('rejects location ping with non-finite or out-of-bounds coordinates', async () => {
      const { createShareSession, recordPing } = require('../src/services/trackingService');
      const share = createShareSession({
        userName: 'Boundary Tester',
        latitude: 28.6139,
        longitude: 77.2090
      });
      const { sessionId, token } = share;

      assert.throws(() => {
        recordPing({
          sessionId,
          latitude: 91.0,
          longitude: 77.0,
          token
        });
      }, /Latitude must be between -90 and 90/);

      assert.throws(() => {
        recordPing({
          sessionId,
          latitude: 28.0,
          longitude: 181.0,
          token
        });
      }, /Latitude must be between -90 and 90/);
    });
  });
});
