/**
 * Live Guardian Tracking & WebSocket Stream Test Suite
 * Comprehensive verification of REST endpoints and WebSocket room-based pub/sub.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { WebSocket } = require('ws');

const { app } = require('../src/app');
const { server, wss, broadcastLocationUpdate, broadcastStreamTerminate, trackingRooms } = require('../src/server');
const { db } = require('../src/data/store');

describe('Live Guardian Tracking & WebSocket Stream', () => {
  let testServer;
  let baseUrl;
  let wsUrl;
  let port;

  before(async () => {
    process.env.NODE_ENV = 'test';
    db.reset();

    testServer = server;
    await new Promise((resolve) => {
      // Close if already listening, or listen on ephemeral port 0
      if (testServer.listening) {
        port = testServer.address().port;
        baseUrl = `http://127.0.0.1:${port}`;
        wsUrl = `ws://127.0.0.1:${port}/ws/sos`;
        return resolve();
      }
      testServer.listen(0, '127.0.0.1', () => {
        port = testServer.address().port;
        baseUrl = `http://127.0.0.1:${port}`;
        wsUrl = `ws://127.0.0.1:${port}/ws/sos`;
        resolve();
      });
    });
  });

  beforeEach(() => {
    db.reset();
  });

  after(async () => {
    if (wss) {
      try {
        wss.close();
      } catch (_) {}
    }
    if (testServer && testServer.listening) {
      await new Promise((resolve) => testServer.close(resolve));
    }
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

  // Wait for the first incoming WS frame satisfying `predicate`, or reject on timeout.
  function waitForMessage(ws, predicate, timeoutMs = 1500) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        ws.removeListener('message', onMessage);
        reject(new Error('Timed out waiting for expected WebSocket message'));
      }, timeoutMs);

      function onMessage(data) {
        let msg;
        try {
          msg = JSON.parse(data.toString());
        } catch (_) {
          return;
        }
        if (predicate(msg)) {
          clearTimeout(timer);
          ws.removeListener('message', onMessage);
          resolve(msg);
        }
      }

      ws.on('message', onMessage);
    });
  }

  // =========================================================================
  // 1. REST API: Share Session Creation (/api/v1/location/share-session)
  // =========================================================================
  describe('1. REST API: Share Session Creation', () => {
    it('creates a new tracking session with initial coordinates and expiring token', async () => {
      const payload = {
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 4.5,
        speed: 12.0,
        battery: 92,
        durationMinutes: 45,
        userName: 'Aanya Sharma'
      };

      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.ok(res.body.sessionId, 'Expected sessionId in response');
      assert.ok(res.body.token, 'Expected secret tracking token in response');
      assert.ok(res.body.shareUrl.includes(res.body.sessionId), 'Expected shareUrl to contain sessionId');
      assert.ok(res.body.expiresAt, 'Expected expiresAt timestamp');

      const session = res.body.data.session;
      assert.equal(session.userName, 'Aanya Sharma');
      assert.equal(session.status, 'active');
      assert.equal(session.currentLocation.latitude, 28.6139);
      assert.equal(session.currentLocation.longitude, 77.2090);
      assert.equal(session.breadcrumbs.length, 1);
    });

    it('rejects session creation with missing coordinates returning 400', async () => {
      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { userName: 'Incomplete User' }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'MISSING_COORDINATES');
    });

    it('rejects session creation with out-of-range coordinates returning 400', async () => {
      const res = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 95.0, // Invalid: > 90
          longitude: 77.2090
        }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_COORDINATES');
    });
  });

  // =========================================================================
  // 2. REST API: Track Session Retrieval (/api/v1/location/track/:sessionId)
  // =========================================================================
  describe('2. REST API: Track Session Retrieval', () => {
    it('retrieves active session metadata, current location, and breadcrumbs history', async () => {
      // 1. Create session
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          userName: 'Rohan Mehra'
        }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      // 2. Query session with valid token (via query param)
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${token}`);
      assert.equal(trackRes.status, 200);
      assert.equal(trackRes.body.success, true);
      assert.equal(trackRes.body.data.sessionId, sessionId);
      assert.equal(trackRes.body.data.userName, 'Rohan Mehra');
      assert.equal(trackRes.body.data.status, 'active');
      assert.equal(trackRes.body.data.breadcrumbs.length, 1);
    });

    it('accepts the tracking token via Authorization: Bearer header', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest(`/api/v1/location/track/${sessionId}`, {
        headers: { Authorization: `Bearer ${createRes.body.token}` }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.sessionId, sessionId);
    });

    it('returns 404 SESSION_NOT_FOUND when requesting non-existent tracking session', async () => {
      const res = await apiRequest('/api/v1/location/track/trk_non_existent_9999');
      assert.equal(res.status, 404);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'SESSION_NOT_FOUND');
    });

    it('rejects retrieval with a wrong tracking token returning 401 INVALID_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest(`/api/v1/location/track/${sessionId}?token=deadbeefwrongtoken`);
      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_TRACKING_TOKEN');
    });

    it('rejects retrieval without any tracking token returning 401 MISSING_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest(`/api/v1/location/track/${sessionId}`);
      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'MISSING_TRACKING_TOKEN');
    });
  });

  // =========================================================================
  // 3. REST API: Breadcrumb Location Pings (/api/v1/location/ping)
  // =========================================================================
  describe('3. REST API: Breadcrumb Location Pings', () => {
    it('appends breadcrumb points to active session and updates currentLocation', async () => {
      // 1. Create session
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          speed: 0
        }
      });
      const sessionId = createRes.body.sessionId;
      const authHeaders = { Authorization: `Bearer ${createRes.body.token}` };

      // 2. Send ping 1
      const ping1 = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        headers: authHeaders,
        body: {
          sessionId,
          latitude: 28.6145,
          longitude: 77.2095,
          speed: 18.5,
          battery: 89,
          accuracy: 3.2
        }
      });
      assert.equal(ping1.status, 200);
      assert.equal(ping1.body.data.pointCount, 2);
      assert.equal(ping1.body.data.currentLocation.latitude, 28.6145);

      // 3. Send ping 2
      const ping2 = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        headers: authHeaders,
        body: {
          sessionId,
          latitude: 28.6152,
          longitude: 77.2102,
          speed: 24.1,
          battery: 88,
          accuracy: 2.8
        }
      });
      assert.equal(ping2.status, 200);
      assert.equal(ping2.body.data.pointCount, 3);

      // 4. Verify full trail via track endpoint
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}`, { headers: authHeaders });
      assert.equal(trackRes.body.data.breadcrumbs.length, 3);
      assert.equal(trackRes.body.data.currentLocation.latitude, 28.6152);
      assert.equal(trackRes.body.data.currentLocation.speed, 24.1);
    });

    it('rejects a ping carrying a wrong tracking token returning 401 INVALID_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        body: {
          sessionId,
          latitude: 28.6145,
          longitude: 77.2095,
          token: 'totally-wrong-token'
        }
      });
      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_TRACKING_TOKEN');
    });

    it('rejects a ping on an existing session with no tracking token returning 401 MISSING_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        body: { sessionId, latitude: 28.6145, longitude: 77.2095 }
      });
      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'MISSING_TRACKING_TOKEN');
    });

    it('rejects ping without sessionId with 400 MISSING_SESSION_ID', async () => {
      const res = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090
        }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'MISSING_SESSION_ID');
    });

    it('rejects ping for non-existent session with 404 SESSION_NOT_FOUND', async () => {
      const res = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        body: {
          sessionId: 'trk_unknown_12345',
          latitude: 28.6139,
          longitude: 77.2090
        }
      });
      assert.equal(res.status, 404);
      assert.equal(res.body.error.code, 'SESSION_NOT_FOUND');
    });

    it('rejects ping after stream termination with 400 SESSION_ENDED', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;
      const authHeaders = { Authorization: `Bearer ${createRes.body.token}` };

      // Terminate session (token required)
      const termRes = await apiRequest(`/api/v1/location/terminate/${sessionId}`, {
        method: 'POST',
        headers: authHeaders
      });
      assert.equal(termRes.status, 200);

      // Ping after termination
      const pingRes = await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        headers: authHeaders,
        body: {
          sessionId,
          latitude: 28.6145,
          longitude: 77.2095
        }
      });
      assert.equal(pingRes.status, 400);
      assert.equal(pingRes.body.error.code, 'SESSION_ENDED');
    });

    it('rejects termination with a wrong tracking token returning 401 INVALID_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const res = await apiRequest(`/api/v1/location/terminate/${sessionId}`, {
        method: 'POST',
        body: { token: 'nope-not-the-token' }
      });
      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_TRACKING_TOKEN');

      // Session must remain active after a rejected termination
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${createRes.body.token}`);
      assert.equal(trackRes.body.data.status, 'active');
    });
  });

  // =========================================================================
  // 4. Real-Time WebSocket Pub/Sub: Room Subscription & Live Broadcast
  // =========================================================================
  describe('4. Real-Time WebSocket Pub/Sub (/ws/sos)', () => {
    it('subscribes guardian to session and receives SUBSCRIBED_TRACKING & TRACKING_SNAPSHOT', async () => {
      // 1. Create tracking session in DB
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          userName: 'Priya Patel'
        }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      const ws = new WebSocket(wsUrl);

      // Wait for welcome message
      await new Promise((resolve) => ws.once('message', resolve));

      // Send SUBSCRIBE_TRACKING
      const messages = [];
      const subPromise = new Promise((resolve) => {
        ws.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          messages.push(msg);
          if (messages.length >= 2) resolve();
        });
      });

      ws.send(JSON.stringify({
        type: 'SUBSCRIBE_TRACKING',
        sessionId,
        token
      }));

      await subPromise;

      const ack = messages.find((m) => m.type === 'SUBSCRIBED_TRACKING');
      const snapshot = messages.find((m) => m.type === 'TRACKING_SNAPSHOT');

      assert.ok(ack, 'Expected SUBSCRIBED_TRACKING ack');
      assert.equal(ack.sessionId, sessionId);
      assert.ok(snapshot, 'Expected initial TRACKING_SNAPSHOT');
      assert.equal(snapshot.session.userName, 'Priya Patel');

      ws.close();
    });

    it('relays LOCATION_STREAM_UPDATE from broadcaster to subscribed guardians in real time', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      const broadcaster = new WebSocket(wsUrl);
      const guardian1 = new WebSocket(wsUrl);
      const guardian2 = new WebSocket(wsUrl);
      const bystander = new WebSocket(wsUrl); // connected but NOT subscribed to this session

      // Wait for welcomes
      await Promise.all([
        new Promise((resolve) => broadcaster.once('message', resolve)),
        new Promise((resolve) => guardian1.once('message', resolve)),
        new Promise((resolve) => guardian2.once('message', resolve)),
        new Promise((resolve) => bystander.once('message', resolve))
      ]);

      // Guardian 1 and Guardian 2 subscribe
      guardian1.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token }));
      guardian2.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token }));

      // Wait a moment for subscription registration
      await new Promise((resolve) => setTimeout(resolve, 30));

      // Setup listeners for live telemetry
      const g1Promise = new Promise((resolve) => {
        guardian1.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'LOCATION_STREAM_UPDATE') resolve(msg);
        });
      });

      const g2Promise = new Promise((resolve) => {
        guardian2.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'LOCATION_STREAM_UPDATE') resolve(msg);
        });
      });

      let bystanderGotUpdate = false;
      bystander.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'LOCATION_STREAM_UPDATE' && msg.sessionId === sessionId) {
          bystanderGotUpdate = true;
        }
      });

      // Broadcaster sends telemetry stream update
      broadcaster.send(JSON.stringify({
        type: 'LOCATION_STREAM_UPDATE',
        sessionId,
        token,
        latitude: 28.6200,
        longitude: 77.2150,
        speed: 25.4,
        battery: 84,
        accuracy: 3.1,
        timestamp: new Date().toISOString()
      }));

      const [update1, update2] = await Promise.all([g1Promise, g2Promise]);

      assert.equal(update1.type, 'LOCATION_STREAM_UPDATE');
      assert.equal(update1.sessionId, sessionId);
      assert.equal(update1.latitude, 28.6200);
      assert.equal(update1.longitude, 77.2150);
      assert.equal(update1.speed, 25.4);
      assert.equal(update1.battery, 84);
      assert.ok(update1.relayedAt, 'Expected relayedAt timestamp');

      assert.equal(update2.latitude, 28.6200);
      assert.equal(bystanderGotUpdate, false, 'Unsubscribed bystander must not receive room stream updates');

      broadcaster.close();
      guardian1.close();
      guardian2.close();
      bystander.close();
    });

    it('relays REST ping updates to WebSocket-subscribed guardians', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      const guardian = new WebSocket(wsUrl);
      await new Promise((resolve) => guardian.once('message', resolve));

      guardian.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token }));
      await new Promise((resolve) => setTimeout(resolve, 30));

      const updatePromise = new Promise((resolve) => {
        guardian.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'LOCATION_STREAM_UPDATE') resolve(msg);
        });
      });

      // Broadcaster sends REST ping
      await apiRequest('/api/v1/location/ping', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: {
          sessionId,
          latitude: 28.6250,
          longitude: 77.2200,
          speed: 31.0,
          battery: 79,
          accuracy: 4.0
        }
      });

      const update = await updatePromise;
      assert.equal(update.sessionId, sessionId);
      assert.equal(update.latitude, 28.6250);
      assert.equal(update.speed, 31.0);

      guardian.close();
    });

    it('broadcasts STREAM_TERMINATE to guardians when session terminates', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      const broadcaster = new WebSocket(wsUrl);
      const guardian = new WebSocket(wsUrl);

      await Promise.all([
        new Promise((resolve) => broadcaster.once('message', resolve)),
        new Promise((resolve) => guardian.once('message', resolve))
      ]);

      guardian.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token }));
      await new Promise((resolve) => setTimeout(resolve, 30));

      const termPromise = new Promise((resolve) => {
        guardian.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'STREAM_TERMINATE') resolve(msg);
        });
      });

      broadcaster.send(JSON.stringify({
        type: 'STREAM_TERMINATE',
        sessionId,
        token,
        reason: 'User arrived safely at destination'
      }));

      const termMsg = await termPromise;
      assert.equal(termMsg.type, 'STREAM_TERMINATE');
      assert.equal(termMsg.sessionId, sessionId);
      assert.equal(termMsg.reason, 'User arrived safely at destination');

      broadcaster.close();
      guardian.close();
    });

    it('rejects SUBSCRIBE_TRACKING with a wrong token returning ERROR INVALID_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const ws = new WebSocket(wsUrl);
      await new Promise((resolve) => ws.once('message', resolve));

      const errPromise = waitForMessage(ws, (m) => m.type === 'ERROR');
      ws.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token: 'wrong-subscribe-token' }));

      const err = await errPromise;
      assert.equal(err.type, 'ERROR');
      assert.equal(err.code, 'INVALID_TRACKING_TOKEN');

      ws.close();
    });

    it('rejects SUBSCRIBE_TRACKING without a token returning ERROR MISSING_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const ws = new WebSocket(wsUrl);
      await new Promise((resolve) => ws.once('message', resolve));

      const errPromise = waitForMessage(ws, (m) => m.type === 'ERROR');
      ws.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId }));

      const err = await errPromise;
      assert.equal(err.code, 'MISSING_TRACKING_TOKEN');

      ws.close();
    });

    it('rejects LOCATION_STREAM_UPDATE with a wrong token and does not broadcast to guardians', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;
      const token = createRes.body.token;

      const broadcaster = new WebSocket(wsUrl);
      const guardian = new WebSocket(wsUrl);
      await Promise.all([
        new Promise((resolve) => broadcaster.once('message', resolve)),
        new Promise((resolve) => guardian.once('message', resolve))
      ]);

      guardian.send(JSON.stringify({ type: 'SUBSCRIBE_TRACKING', sessionId, token }));
      await waitForMessage(guardian, (m) => m.type === 'SUBSCRIBED_TRACKING');

      let guardianSawUpdate = false;
      guardian.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'LOCATION_STREAM_UPDATE') guardianSawUpdate = true;
      });

      const errPromise = waitForMessage(broadcaster, (m) => m.type === 'ERROR');
      broadcaster.send(JSON.stringify({
        type: 'LOCATION_STREAM_UPDATE',
        sessionId,
        token: 'bad-stream-token',
        latitude: 28.6200,
        longitude: 77.2150
      }));

      const err = await errPromise;
      assert.equal(err.code, 'INVALID_TRACKING_TOKEN');

      // Give any (incorrect) broadcast a chance to arrive before asserting absence
      await new Promise((resolve) => setTimeout(resolve, 50));
      assert.equal(guardianSawUpdate, false, 'Unauthorized update must not reach subscribers');

      broadcaster.close();
      guardian.close();
    });

    it('rejects STREAM_TERMINATE with a wrong token returning ERROR INVALID_TRACKING_TOKEN', async () => {
      const createRes = await apiRequest('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      const sessionId = createRes.body.sessionId;

      const broadcaster = new WebSocket(wsUrl);
      await new Promise((resolve) => broadcaster.once('message', resolve));

      const errPromise = waitForMessage(broadcaster, (m) => m.type === 'ERROR');
      broadcaster.send(JSON.stringify({
        type: 'STREAM_TERMINATE',
        sessionId,
        token: 'wrong-terminate-token',
        reason: 'should not apply'
      }));

      const err = await errPromise;
      assert.equal(err.code, 'INVALID_TRACKING_TOKEN');

      // Session must remain active after a rejected WebSocket termination
      const trackRes = await apiRequest(`/api/v1/location/track/${sessionId}?token=${createRes.body.token}`);
      assert.equal(trackRes.body.data.status, 'active');

      broadcaster.close();
    });
  });
});
