/**
 * Check-in Timer Dead-Man Switch Test Suite (F3-3)
 *
 * Verifies:
 * 1. Validation of checkInIntervalMin (1-1440 min, rejects <= 0, > 1440, non-integers)
 * 2. Session creation with check-in timer initialization (deadline set, missedCheckIns = 0)
 * 3. Gating and snapshot retrieval via GET /api/v1/location/track/:sessionId
 * 4. Deterministic zero-sleep deadline expiration via DB timestamp mutation & processCheckInDeadlines
 * 5. Real-time WebSocket CHECKIN_MISSED broadcast to subscribed tracking rooms
 * 6. Broadcaster ping resets checkInDeadline and clears missedCheckIns (via REST and WS)
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');

const { server, wss } = require('../src/server');
const { db } = require('../src/data/store');
const trackingService = require('../src/services/trackingService');

describe('Check-in Timer Dead-Man Switch Tests (F3-3)', () => {
  let testPort;
  let baseUrl;
  let wsUrl;

  before(async () => {
    process.env.NODE_ENV = 'test';
    db.reset();

    if (server.listening) {
      testPort = server.address().port;
      baseUrl = `http://127.0.0.1:${testPort}`;
      wsUrl = `ws://127.0.0.1:${testPort}/ws/sos`;
    } else {
      await new Promise((resolve, reject) => {
        server.listen(0, '127.0.0.1', (err) => {
          if (err) return reject(err);
          testPort = server.address().port;
          baseUrl = `http://127.0.0.1:${testPort}`;
          wsUrl = `ws://127.0.0.1:${testPort}/ws/sos`;
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

  // ===========================================================================
  // 1. Validation & Initialization of checkInIntervalMin
  // ===========================================================================
  describe('1. Check-in Interval Validation & Initialization', () => {
    it('rejects invalid checkInIntervalMin values (< 1, > 1440, non-integer, non-numeric) with 400 INVALID_CHECKIN_INTERVAL', async () => {
      const invalidValues = [0, -1, -30, 1441, 10000, 15.5, 'not-a-number', true];

      for (const val of invalidValues) {
        const res = await apiRequest('/api/v1/location/share-session', {
          method: 'POST',
          body: {
            latitude: 28.6139,
            longitude: 77.2090,
            checkInIntervalMin: val
          }
        });

        assert.equal(res.status, 400, `Expected 400 for checkInIntervalMin=${val}`);
        assert.equal(res.body.error.code, 'INVALID_CHECKIN_INTERVAL', `Expected code INVALID_CHECKIN_INTERVAL for val=${val}`);
      }
    });

    it('defaults to checkInIntervalMin=null, checkInDeadline=null, missedCheckIns=0 when omitted or null', async () => {
      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          durationMinutes: 60
        }
      });

      assert.equal(res.status, 201);
      const session = res.body.data.session;
      assert.equal(session.checkInIntervalMin, null);
      assert.equal(session.checkInDeadline, null);
      assert.equal(session.missedCheckIns, 0);
    });

    it('initializes checkInDeadline in future and missedCheckIns=0 when valid checkInIntervalMin is provided', async () => {
      const nowBefore = Date.now();
      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          durationMinutes: 120,
          checkInIntervalMin: 30
        }
      });

      assert.equal(res.status, 201);
      const session = res.body.data.session;
      assert.equal(session.checkInIntervalMin, 30);
      assert.equal(session.missedCheckIns, 0);
      assert.ok(session.checkInDeadline);

      const deadlineMs = new Date(session.checkInDeadline).getTime();
      const expectedDeadlineMs = nowBefore + 30 * 60 * 1000;
      assert.ok(Math.abs(deadlineMs - expectedDeadlineMs) < 5000, 'Deadline should be ~30 minutes in the future');
    });

    it('accepts snake_case check_in_interval_min parameter', async () => {
      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          check_in_interval_min: 15
        }
      });

      assert.equal(res.status, 201);
      const session = res.body.data.session;
      assert.equal(session.checkInIntervalMin, 15);
      assert.equal(session.missedCheckIns, 0);
      assert.ok(session.checkInDeadline);
    });
  });

  // ===========================================================================
  // 2. Telemetry Retrieval & Gating (GET /api/v1/location/track/:sessionId)
  // ===========================================================================
  describe('2. Telemetry Retrieval & Credential Gating', () => {
    it('exposes checkInIntervalMin, checkInDeadline, and missedCheckIns in getTrack response data', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 45
        }
      });
      const { sessionId, token } = createRes.body;

      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
      assert.equal(trackRes.status, 200);
      const data = trackRes.body.data;

      assert.equal(data.checkInIntervalMin, 45);
      assert.ok(data.checkInDeadline);
      assert.equal(data.missedCheckIns, 0);

      // Also on data.session
      assert.equal(data.session.checkInIntervalMin, 45);
      assert.ok(data.session.checkInDeadline);
      assert.equal(data.session.missedCheckIns, 0);
    });

    it('enforces token requirement: rejects requests without token or with forged token', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 60
        }
      });
      const { sessionId } = createRes.body;

      const noTokenRes = await apiRequest(`/api/v1/location/track/${sessionId}`);
      assert.equal(noTokenRes.status, 401);
      assert.equal(noTokenRes.body.error.code, 'MISSING_TRACKING_TOKEN');

      const badTokenRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=invalid_forged_token`);
      assert.equal(badTokenRes.status, 401);
      assert.equal(badTokenRes.body.error.code, 'INVALID_TRACKING_TOKEN');
    });
  });

  // ===========================================================================
  // 3. Deterministic Zero-Sleep Deadline Expiration & Process Ticks
  // ===========================================================================
  describe('3. Deterministic Deadline Expiration via processCheckInDeadlines', () => {
    it('detects missed check-in, increments missedCheckIns, and advances checkInDeadline', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 15
        }
      });
      const { sessionId, token } = createRes.body;

      // Time-shift checkInDeadline to 10 seconds in the past
      const pastDeadline = new Date(Date.now() - 10000).toISOString();
      db.updateTrackingSession(sessionId, { checkInDeadline: pastDeadline });

      const now = new Date();
      const missedEvents = [];
      const missed = trackingService.processCheckInDeadlines(now, (evt) => {
        missedEvents.push(evt);
      });

      assert.equal(missed.length, 1);
      assert.equal(missed[0].id, sessionId);
      assert.equal(missed[0].missedCheckIns, 1);

      // Verify checkInDeadline was advanced by 15 min into the future
      const newDeadlineMs = new Date(missed[0].checkInDeadline).getTime();
      assert.ok(newDeadlineMs > now.getTime(), 'Next deadline must be in the future');

      // Verify broadcast helper was invoked
      assert.equal(missedEvents.length, 1);
      assert.equal(missedEvents[0].sessionId, sessionId);
      assert.equal(missedEvents[0].missedCheckIns, 1);
      assert.ok(missedEvents[0].checkInDeadline);

      // Verify persistence in SQLite
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
      assert.equal(trackRes.body.data.missedCheckIns, 1);
      assert.equal(trackRes.body.data.checkInDeadline, missed[0].checkInDeadline);

      // Immediate re-run at the same time does NOT re-fire
      const secondRun = trackingService.processCheckInDeadlines(now);
      assert.equal(secondRun.length, 0, 'Must not re-fire within the newly armed deadline cycle');
    });

    it('increments missedCheckIns sequentially on subsequent missed cycles', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 15
        }
      });
      const { sessionId } = createRes.body;

      // Cycle 1: Mutate to past -> miss 1
      db.updateTrackingSession(sessionId, { checkInDeadline: new Date(Date.now() - 5000).toISOString() });
      const miss1 = trackingService.processCheckInDeadlines(new Date());
      assert.equal(miss1[0].missedCheckIns, 1);

      // Cycle 2: Mutate advanced deadline to past again -> miss 2
      db.updateTrackingSession(sessionId, { checkInDeadline: new Date(Date.now() - 5000).toISOString() });
      const miss2 = trackingService.processCheckInDeadlines(new Date());
      assert.equal(miss2[0].missedCheckIns, 2);
    });
  });

  // ===========================================================================
  // 4. Real-Time WebSocket CHECKIN_MISSED Broadcast
  // ===========================================================================
  describe('4. WebSocket CHECKIN_MISSED Room Broadcast', () => {
    it('broadcasts CHECKIN_MISSED event to subscribed tracking room clients', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 15
        }
      });
      const { sessionId, token } = createRes.body;

      // 1. Connect WS guardian client
      const wsClient = new WebSocket(wsUrl);
      const incoming = [];

      wsClient.on('message', (raw) => {
        try {
          incoming.push(JSON.parse(raw.toString()));
        } catch (_) {}
      });

      await new Promise((resolve, reject) => {
        wsClient.on('open', resolve);
        wsClient.on('error', reject);
      });

      // 2. Subscribe to tracking stream
      wsClient.send(JSON.stringify({
        type: 'SUBSCRIBE_TRACKING',
        sessionId,
        token
      }));

      for (let i = 0; i < 20; i++) {
        if (incoming.some((m) => m.type === 'SUBSCRIBED_TRACKING')) break;
        await new Promise((r) => setTimeout(r, 10));
      }
      assert.ok(incoming.some((m) => m.type === 'SUBSCRIBED_TRACKING'), 'Must receive SUBSCRIBED_TRACKING');

      // 3. Time-shift checkInDeadline and process
      db.updateTrackingSession(sessionId, {
        checkInDeadline: new Date(Date.now() - 5000).toISOString()
      });

      trackingService.processCheckInDeadlines(new Date());

      // 4. Await CHECKIN_MISSED packet
      for (let i = 0; i < 30; i++) {
        if (incoming.some((m) => m.type === 'CHECKIN_MISSED')) break;
        await new Promise((r) => setTimeout(r, 10));
      }

      const missedMsg = incoming.find((m) => m.type === 'CHECKIN_MISSED');
      assert.ok(missedMsg, 'Guardian client must receive CHECKIN_MISSED WebSocket message');
      assert.equal(missedMsg.sessionId, sessionId);
      assert.equal(missedMsg.missedCheckIns, 1);
      assert.ok(missedMsg.checkInDeadline);
      assert.ok(missedMsg.timestamp);

      wsClient.terminate();
    });
  });

  // ===========================================================================
  // 5. Broadcaster Ping Resets Deadline and Clears Missed Counter
  // ===========================================================================
  describe('5. Broadcaster Ping Reset Lifecycle', () => {
    it('resets checkInDeadline and clears missedCheckIns to 0 on REST ping', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 30
        }
      });
      const { sessionId, token } = createRes.body;

      // Simulate missed check-in state
      db.updateTrackingSession(sessionId, {
        checkInDeadline: new Date(Date.now() - 5000).toISOString()
      });
      trackingService.processCheckInDeadlines(new Date());

      // Verify session has missedCheckIns = 1
      const beforePing = db.findTrackingSessionById(sessionId);
      assert.equal(beforePing.missedCheckIns, 1);

      // Broadcaster checks in via REST ping
      const pingBefore = Date.now();
      const pingRes = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`
        },
        body: {
          sessionId,
          latitude: 28.6150,
          longitude: 77.2100,
          speed: 5.0,
          battery: 92,
          accuracy: 4.0
        }
      });

      assert.equal(pingRes.status, 200);

      // Verify track endpoint confirms reset
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
      assert.equal(trackRes.status, 200);
      const data = trackRes.body.data;

      assert.equal(data.missedCheckIns, 0, 'missedCheckIns must be reset to 0 after ping');
      const resetDeadlineMs = new Date(data.checkInDeadline).getTime();
      const expectedResetDeadlineMs = pingBefore + 30 * 60 * 1000;
      assert.ok(
        Math.abs(resetDeadlineMs - expectedResetDeadlineMs) < 5000,
        'checkInDeadline must be re-armed to ~30 mins from ping time'
      );
    });

    it('resets checkInDeadline and clears missedCheckIns on WebSocket LOCATION_STREAM_UPDATE', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          checkInIntervalMin: 20
        }
      });
      const { sessionId, token } = createRes.body;

      // Simulate missed check-in state
      db.updateTrackingSession(sessionId, {
        checkInDeadline: new Date(Date.now() - 5000).toISOString()
      });
      trackingService.processCheckInDeadlines(new Date());
      assert.equal(db.findTrackingSessionById(sessionId).missedCheckIns, 1);

      // Connect broadcaster WebSocket client
      const wsClient = new WebSocket(wsUrl);
      await new Promise((resolve) => wsClient.on('open', resolve));

      const wsBefore = Date.now();
      wsClient.send(JSON.stringify({
        type: 'LOCATION_STREAM_UPDATE',
        sessionId,
        token,
        latitude: 28.6160,
        longitude: 77.2110,
        speed: 10.0,
        battery: 85,
        accuracy: 3.0,
        timestamp: new Date().toISOString()
      }));

      // Allow WS message processing
      await new Promise((r) => setTimeout(r, 50));

      const afterWsPing = db.findTrackingSessionById(sessionId);
      assert.equal(afterWsPing.missedCheckIns, 0, 'missedCheckIns must reset to 0 after WS update');
      const wsDeadlineMs = new Date(afterWsPing.checkInDeadline).getTime();
      const expectedDeadlineMs = wsBefore + 20 * 60 * 1000;
      assert.ok(
        Math.abs(wsDeadlineMs - expectedDeadlineMs) < 5000,
        'checkInDeadline must be re-armed to ~20 mins from WS update'
      );

      wsClient.terminate();
    });
  });
});
