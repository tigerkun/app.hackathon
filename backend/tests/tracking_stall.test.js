/**
 * Breadcrumb-Stall Guardian Alert Test Suite (F3-2)
 *
 * Verifies:
 * 1. Session creation initialization (lastActivityAt set, stallDetected === false)
 * 2. Deterministic zero-sleep time-shifted stall detection (> 120s => stallDetected: true)
 * 3. Ping recovery restores active status (lastActivityAt refreshed, stallDetected: false)
 * 4. Ended session immunity against stall detection
 * 5. Tracking token credential gating & invariant protection (401 on missing/invalid token, zero hash leakage)
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const { server, wss } = require('../src/server');
const { db } = require('../src/data/store');

describe('Breadcrumb-Stall Guardian Alert Tests (F3-2)', () => {
  let testPort;
  let baseUrl;

  before(async () => {
    process.env.NODE_ENV = 'test';
    db.reset();

    if (server.listening) {
      testPort = server.address().port;
      baseUrl = `http://127.0.0.1:${testPort}`;
    } else {
      await new Promise((resolve, reject) => {
        server.listen(0, '127.0.0.1', (err) => {
          if (err) return reject(err);
          testPort = server.address().port;
          baseUrl = `http://127.0.0.1:${testPort}`;
          resolve();
        });
      });
    }
  });

  after(async () => {
    for (const client of wss.clients) {
      try { client.terminate(); } catch (_) {}
    }
    if (server && server.listening) {
      await new Promise((resolve) => server.close(resolve));
    }
  });

  beforeEach(() => {
    db.reset();
  });

  async function apiRequest(path, options = {}) {
    const url = `${baseUrl}${path}`;
    const headers = {
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };

    const res = await fetch(url, {
      method: options.method || 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined
    });

    let body = null;
    try {
      body = await res.json();
    } catch (_) {}

    return {
      status: res.status,
      headers: res.headers,
      body
    };
  }

  it('1. Session creation initializes lastActivityAt and stallDetected === false', async () => {
    const createRes = await apiRequest('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 5.0,
        speed: 1.5,
        durationMinutes: 60,
        userName: 'Priya Traveler'
      }
    });

    assert.equal(createRes.status, 201);
    assert.equal(createRes.body.success, true);
    const { sessionId, token } = createRes.body;
    assert.ok(sessionId.startsWith('trk_'));
    assert.ok(token);

    const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(trackRes.status, 200);
    assert.equal(trackRes.body.success, true);
    const data = trackRes.body.data;

    assert.equal(data.stallDetected, false);
    assert.ok(data.stalledDurationSeconds <= 5);
    assert.ok(data.lastActivityAt);
    assert.equal(data.status, 'active');

    // Both on data and data.session
    assert.equal(data.session.stallDetected, false);
    assert.ok(data.session.stalledDurationSeconds <= 5);
    assert.ok(data.session.lastActivityAt);
  });

  it('2. Time-shift test: stallDetected becomes true and stalledDurationSeconds >= 130 when lastActivityAt is 130s past', async () => {
    const createRes = await apiRequest('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 5.0,
        durationMinutes: 60
      }
    });
    const { sessionId, token } = createRes.body;

    // Artificially time-shift lastActivityAt to 130 seconds ago
    const shiftedTime = new Date(Date.now() - 130000).toISOString();
    const updated = db.updateTrackingSession(sessionId, {
      lastActivityAt: shiftedTime
    });
    assert.equal(updated.lastActivityAt, shiftedTime);

    const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(trackRes.status, 200);
    const data = trackRes.body.data;

    assert.equal(data.stallDetected, true);
    assert.ok(data.stalledDurationSeconds >= 130, `Expected stalledDurationSeconds >= 130, got ${data.stalledDurationSeconds}`);
    assert.equal(data.lastActivityAt, shiftedTime);

    // Verify presence on data.session
    assert.equal(data.session.stallDetected, true);
    assert.ok(data.session.stalledDurationSeconds >= 130);
    assert.equal(data.session.lastActivityAt, shiftedTime);
  });

  it('3. Ping recovery test: POST /api/v1/location/ping refreshes lastActivityAt and clears stall', async () => {
    const createRes = await apiRequest('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        durationMinutes: 60
      }
    });
    const { sessionId, token } = createRes.body;

    // Fast-forward to stalled state (150s ago)
    const pastTime = new Date(Date.now() - 150000).toISOString();
    db.updateTrackingSession(sessionId, {
      lastActivityAt: pastTime
    });

    // Verify currently stalled
    const stalledRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(stalledRes.body.data.stallDetected, true);

    // Broadcaster sends new telemetry ping
    const pingRes = await apiRequest('/api/v1/location/ping', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`
      },
      body: {
        sessionId,
        latitude: 28.6150,
        longitude: 77.2100,
        speed: 12.0,
        battery: 88,
        accuracy: 3.5
      }
    });

    assert.equal(pingRes.status, 200);
    assert.equal(pingRes.body.success, true);

    // Query track again -> stall must be resolved
    const recoveredRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(recoveredRes.status, 200);
    const data = recoveredRes.body.data;

    assert.equal(data.stallDetected, false);
    assert.ok(data.stalledDurationSeconds <= 5);
    const newActivityMs = new Date(data.lastActivityAt).getTime();
    assert.ok(Date.now() - newActivityMs < 5000, 'lastActivityAt should be freshly updated');
  });

  it('4. Termination immunity: ended session does not trigger stall alert even if lastActivityAt is old', async () => {
    const createRes = await apiRequest('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        durationMinutes: 60
      }
    });
    const { sessionId, token } = createRes.body;

    // Terminate session
    const termRes = await apiRequest(`/api/v1/location/terminate/${sessionId}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`
      }
    });
    assert.equal(termRes.status, 200);

    // Artificially set lastActivityAt to 10 minutes ago
    const oldTime = new Date(Date.now() - 600000).toISOString();
    db.updateTrackingSession(sessionId, {
      lastActivityAt: oldTime
    });

    const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(trackRes.status, 200);
    const data = trackRes.body.data;

    assert.equal(data.status, 'ended');
    assert.equal(data.stallDetected, false);
    assert.equal(data.session.stallDetected, false);
  });

  it('5. Invariant test: credential gating strictly enforced and zero hash leakages', async () => {
    const createRes = await apiRequest('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 28.6139,
        longitude: 77.2090,
        durationMinutes: 60
      }
    });
    const { sessionId, token } = createRes.body;

    // Request without token -> 401
    const missingRes = await apiRequest(`/api/v1/location/track/${sessionId}`);
    assert.equal(missingRes.status, 401);
    assert.equal(missingRes.body.error.code, 'MISSING_TRACKING_TOKEN');

    // Request with invalid token -> 401
    const invalidRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=invalid_forged_token`);
    assert.equal(invalidRes.status, 401);
    assert.equal(invalidRes.body.error.code, 'INVALID_TRACKING_TOKEN');

    // Valid token -> 200 and no secret hash leakage
    const validRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
    assert.equal(validRes.status, 200);
    const payloadStr = JSON.stringify(validRes.body);
    assert.ok(!payloadStr.includes('resolveTokenHash'), 'resolveTokenHash must never be exposed');
    assert.ok(!payloadStr.includes('refreshTokenHash'), 'refreshTokenHash must never be exposed');
  });
});
