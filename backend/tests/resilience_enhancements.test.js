/**
 * SafeSphere Production Reliability & UX Enhancements
 * Backend Automated Verification Suite
 * Target: Token refresh resilience, 401 retry simulation, offline SOS ingestion, and breadcrumb precision.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');

describe('SafeSphere Production Resilience & UX Enhancements', () => {
  let serverHarness;

  before(async () => {
    serverHarness = await startTestServer();
  });

  after(async () => {
    if (serverHarness) {
      await serverHarness.close();
    }
  });

  beforeEach(() => {
    db.reset();
  });

  // ===========================================================================
  // 1. Token Refresh & 401 Authentication Resilience
  // ===========================================================================
  describe('Authentication Resilience & Silent Token Refresh', () => {
    it('rejects expired or forged access token with 401 and allows silent refresh recovery', async () => {
      // 1. Register test user
      const registerRes = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Resilience Test User',
          email: 'resilience@safesphere.test',
          phone: '+91 9900011223',
          password: 'Password1234!',
          pin: '9876'
        }
      });
      assert.equal(registerRes.status, 201);
      const { accessToken, refreshToken } = registerRes.body.data;
      assert.ok(accessToken, 'Valid initial access token issued');
      assert.ok(refreshToken, 'Valid initial refresh token issued');

      // 2. Access protected endpoint with valid token
      const meRes = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${accessToken}` }
      });
      assert.equal(meRes.status, 200);
      assert.equal(meRes.body.data.email, 'resilience@safesphere.test');

      // 3. Simulate expired / invalid token hitting 401
      const invalidToken = accessToken.slice(0, -6) + 'xxxxxx';
      const failedRes = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${invalidToken}` }
      });
      assert.equal(failedRes.status, 401);
      assert.equal(failedRes.body.success, false);

      // 4. Client intercepts 401 and silently refreshes using refreshToken
      const refreshRes = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken }
      });
      assert.equal(refreshRes.status, 200);
      assert.equal(refreshRes.body.success, true);
      const newAccessToken = refreshRes.body.accessToken || refreshRes.body.data?.accessToken;
      const newRefreshToken = refreshRes.body.refreshToken || refreshRes.body.data?.refreshToken;
      assert.ok(newAccessToken, 'New rotated access token received');
      assert.ok(newRefreshToken, 'New rotated refresh token received');
      assert.notEqual(newAccessToken, accessToken, 'Access token is fresh');
      assert.notEqual(newRefreshToken, refreshToken, 'Refresh token was rotated');

      // 5. Retried original request with newAccessToken succeeds
      const retryRes = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${newAccessToken}` }
      });
      assert.equal(retryRes.status, 200);
      assert.equal(retryRes.body.data.email, 'resilience@safesphere.test');
    });

    it('enforces refresh token rotation security and revokes reused refresh tokens', async () => {
      // Register and get initial tokens
      const reg = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Rotation Guard User',
          email: 'rotation@safesphere.test',
          phone: '+91 9900011224',
          password: 'Password1234!'
        }
      });
      assert.equal(reg.status, 201);
      const firstRefreshToken = reg.body.data.refreshToken;

      // First refresh: consumes firstRefreshToken and returns secondRefreshToken
      const ref1 = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: firstRefreshToken }
      });
      assert.equal(ref1.status, 200);
      const secondRefreshToken = ref1.body.refreshToken;

      // Malicious or concurrent reuse of firstRefreshToken: must fail with 401
      const reuseRes = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: firstRefreshToken }
      });
      assert.equal(reuseRes.status, 401);
      assert.equal(reuseRes.body.error?.code, 'INVALID_SESSION');
    });
  });

  // ===========================================================================
  // 2. Offline SOS Ingestion & Replay
  // ===========================================================================
  describe('Offline SOS Queue Ingestion & Replay', () => {
    it('successfully ingests queued offline SOS payloads upon network reconnection', async () => {
      // Simulate client device being offline and accumulating queued alerts
      const offlineQueue = [
        {
          latitude: 28.6139,
          longitude: 77.2090,
          accuracy: 5.2,
          batteryLevel: 45,
          alertType: 'CRITICAL_SOS',
          notes: 'Queued offline alert #1'
        },
        {
          latitude: 28.6145,
          longitude: 77.2095,
          accuracy: 4.8,
          batteryLevel: 44,
          alertType: 'CRITICAL_SOS',
          notes: 'Queued offline alert #2'
        }
      ];

      const ingestedAlerts = [];

      // Reconnect and replay queue
      for (const payload of offlineQueue) {
        const res = await serverHarness.request('/api/v1/sos/trigger', {
          method: 'POST',
          body: payload
        });
        assert.equal(res.status, 201, 'Queued alert ingested with 201 Created');
        assert.equal(res.body.success, true);
        const alertId = res.body.data?.id || res.body.id;
        const resolveToken = res.body.resolveToken || res.body.data?.resolveToken;
        assert.ok(alertId, 'Alert assigned unique ID');
        assert.ok(resolveToken, 'Alert assigned self-resolve token');
        ingestedAlerts.push({ alertId, resolveToken });
      }

      assert.equal(ingestedAlerts.length, 2);

      // Verify ingested alert can be marked resolved with resolveToken
      const resolveRes = await serverHarness.request(`/api/v1/sos/${ingestedAlerts[0].alertId}/resolve`, {
        method: 'POST',
        body: {
          id: ingestedAlerts[0].alertId,
          resolveToken: ingestedAlerts[0].resolveToken,
          notes: 'Resolved by citizen after recovery'
        }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');
    });
  });

  // ===========================================================================
  // 3. Guardian Tracking Breadcrumb Trail Delivery
  // ===========================================================================
  describe('Guardian Tracking Breadcrumb Trail Delivery', () => {
    it('records pings and returns complete historical breadcrumbs array with 5-decimal precision', async () => {
      // 1. Create share session
      const createRes = await serverHarness.request('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          userName: 'Explorer User',
          latitude: 28.61393,
          longitude: 77.20902,
          accuracy: 4.0,
          durationMinutes: 30
        }
      });
      assert.equal(createRes.status, 201);
      const sessionId = createRes.body.sessionId;
      const trackingToken = createRes.body.token;
      assert.ok(sessionId, 'Session ID created');
      assert.ok(trackingToken, 'Tracking token issued');

      const authHeaders = { Authorization: `Bearer ${trackingToken}` };

      // 2. Send 2 additional location pings along a trail
      const pings = [
        { latitude: 28.61451, longitude: 77.20952, accuracy: 3.5, speed: 1.2 },
        { latitude: 28.61523, longitude: 77.21014, accuracy: 3.0, speed: 1.4 }
      ];

      for (const ping of pings) {
        const pingRes = await serverHarness.request('/api/v1/location/ping', {
          method: 'POST',
          headers: authHeaders,
          body: {
            sessionId,
            ...ping
          }
        });
        assert.equal(pingRes.status, 200);
      }

      // 3. Guardian fetches tracking session data
      const trackRes = await serverHarness.request(`/api/v1/location/track/${sessionId}`, {
        headers: authHeaders
      });
      assert.equal(trackRes.status, 200);
      const sessionData = trackRes.body.data;

      // 4. Verify breadcrumbs array is present, contains all 3 fixes, and has 5-decimal coordinates
      assert.ok(Array.isArray(sessionData.breadcrumbs), 'breadcrumbs must be an array');
      assert.equal(sessionData.breadcrumbs.length, 3, 'Must contain initial fix + 2 recorded pings');

      const latestCrumb = sessionData.breadcrumbs[sessionData.breadcrumbs.length - 1];
      assert.equal(latestCrumb.latitude, 28.61523);
      assert.equal(latestCrumb.longitude, 77.21014);
      assert.ok(latestCrumb.timestamp, 'Breadcrumb must have a timestamp');
    });
  });
});
