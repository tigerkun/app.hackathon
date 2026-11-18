/**
 * SafeSphere Reports, Markers, and SOS Integration Tests
 * Native Node.js test runner using node:test and node:assert/strict.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { signAccessToken } = require('../src/services/tokenService');

function createTestToken(userOverrides = {}) {
  const user = db.saveUser({
    id: `usr_test_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    name: 'Test User',
    email: `test_${Date.now()}_${Math.random().toString(36).slice(2, 6)}@example.com`,
    phone: '+91 9999900001',
    role: 'citizen',
    passwordHash: 'dummy_hash',
    isActive: true,
    ...userOverrides
  });
  const token = signAccessToken(user, null);
  return { user, token };
}

describe('SafeSphere Community Safety & Emergency API Tests', () => {
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
  // 1. Incident Reports API
  // ===========================================================================
  describe('Incident Reports (/api/v1/reports)', () => {
    it('lists seeded incident reports with count', async () => {
      const res = await serverHarness.request('/api/v1/reports');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(Array.isArray(res.body.data));
      assert.ok(res.body.data.length >= 3, 'Expected at least 3 seeded reports');
    });

    it('creates a new community hazard report returning 201 Created', async () => {
      const payload = {
        type: 'Theft',
        description: 'Unattended bag reported near Gate 4',
        location: 'Rajiv Chowk Metro Station',
        latitude: 28.6328,
        longitude: 77.2197
      };

      const res = await serverHarness.request('/api/v1/reports', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.type, 'Theft');
      assert.equal(res.body.data.status, 'pending');
      assert.ok(res.body.data.id.startsWith('rep_'));
    });

    it('rejects report submission with missing description with 400 Bad Request', async () => {
      const res = await serverHarness.request('/api/v1/reports', {
        method: 'POST',
        body: { location: 'Connaught Place' }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });
  });

  // ===========================================================================
  // 2. Safety Markers & Spatial Proximity Search
  // ===========================================================================
  describe('Safety Markers (/api/v1/markers)', () => {
    it('lists seeded safety markers', async () => {
      const res = await serverHarness.request('/api/v1/markers');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(Array.isArray(res.body.data));
      assert.ok(res.body.data.length >= 3, 'Expected at least 3 seeded safety markers');
    });

    it('calculates nearby safety markers using Haversine formula and sorts by proximity', async () => {
      // Coordinates at Connaught Place Central (28.6315, 77.2167)
      const res = await serverHarness.request('/api/v1/markers/nearby?lat=28.6315&lon=77.2167&radius=10');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.length > 0);

      // Verify markers have calculated distanceKm property
      const first = res.body.data[0];
      assert.ok(typeof first.distanceKm === 'number');
      assert.ok(first.distanceKm <= 1.0, 'CP police marker should be within 1km');

      // Verify sorting ascending by distanceKm
      for (let i = 0; i < res.body.data.length - 1; i++) {
        assert.ok(res.body.data[i].distanceKm <= res.body.data[i + 1].distanceKm);
      }
    });

    it('enforces least privilege on marker creation: unauth and standard users get isVerified: false, responder gets true', async () => {
      // 1. Unauthenticated creation with client isVerified: true attempted
      const unauthRes = await serverHarness.request('/api/v1/markers', {
        method: 'POST',
        body: {
          name: 'Community Watch Stand',
          latitude: 28.6300,
          longitude: 77.2150,
          isVerified: true
        }
      });
      assert.equal(unauthRes.status, 201);
      assert.equal(unauthRes.body.data.isVerified, false, 'Client-sent isVerified must be discarded for unauth');

      // 2. Standard citizen creation
      const citizen = createTestToken({ role: 'citizen' });
      const citizenRes = await serverHarness.request('/api/v1/markers', {
        method: 'POST',
        headers: { Authorization: `Bearer ${citizen.token}` },
        body: {
          name: 'Citizen Reported Kiosk',
          latitude: 28.6310,
          longitude: 77.2160,
          isVerified: true
        }
      });
      assert.equal(citizenRes.status, 201);
      assert.equal(citizenRes.body.data.isVerified, false, 'Standard citizen must not create verified marker');

      // 3. First responder creation
      const responder = createTestToken({ role: 'first_responder' });
      const responderRes = await serverHarness.request('/api/v1/markers', {
        method: 'POST',
        headers: { Authorization: `Bearer ${responder.token}` },
        body: {
          name: 'Official Mobile PCR Van',
          latitude: 28.6320,
          longitude: 77.2170
        }
      });
      assert.equal(responderRes.status, 201);
      assert.equal(responderRes.body.data.isVerified, true, 'First responder creates verified marker');
    });
  });

  // ===========================================================================
  // 3. Emergency SOS API
  // ===========================================================================
  describe('Emergency SOS Alerts (/api/v1/sos)', () => {
    it('triggers SOS alert returning 201 Created with active status', async () => {
      const payload = {
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 5.2,
        batteryLevel: 88,
        alertType: 'CRITICAL_SOS',
        notes: 'Emergency assistance requested'
      };

      const res = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.status, 'active');
      assert.ok(res.body.data.id.startsWith('sos_'));

      const sosId = res.body.data.id;

      // Verify it appears in active alerts
      const activeRes = await serverHarness.request('/api/v1/sos/active');
      assert.equal(activeRes.status, 200);
      const activeIds = activeRes.body.data.map((a) => a.id);
      assert.ok(activeIds.includes(sosId));

      // Resolve alert with authorized responder token
      const responder = createTestToken({ role: 'first_responder' });
      const resolveRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${responder.token}` },
        body: { notes: 'Citizen reported safe by responder team' }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');
      assert.ok(resolveRes.body.data.resolvedAt);
    });

    it('registered user alert: owner resolve succeeds', async () => {
      const owner = createTestToken({ role: 'citizen' });
      const triggerRes = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${owner.token}` },
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      assert.equal(triggerRes.status, 201);
      const sosId = triggerRes.body.data.id;

      const resolveRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${owner.token}` },
        body: { notes: 'Resolved by owner' }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');
    });

    it('registered user alert: wrong or missing token returns 401', async () => {
      const owner = createTestToken({ role: 'citizen' });
      const triggerRes = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${owner.token}` },
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      const sosId = triggerRes.body.data.id;

      // Missing token
      const noAuthRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        body: { notes: 'Unauthenticated attempt' }
      });
      assert.equal(noAuthRes.status, 401);
      assert.equal(noAuthRes.body.error.code, 'UNAUTHORIZED_RESOLVE');

      // Invalid token
      const badAuthRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: 'Bearer invalid.token' },
        body: { notes: 'Bad token attempt' }
      });
      assert.equal(badAuthRes.status, 401);
    });

    it('registered user alert: non-owner citizen returns 403', async () => {
      const owner = createTestToken({ role: 'citizen' });
      const stranger = createTestToken({ role: 'citizen' });

      const triggerRes = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${owner.token}` },
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      const sosId = triggerRes.body.data.id;

      const resolveRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${stranger.token}` },
        body: { notes: 'Stranger attempting resolution' }
      });
      assert.equal(resolveRes.status, 403);
      assert.equal(resolveRes.body.error.code, 'FORBIDDEN_RESOLVE');
    });

    it('anonymous alert resolve policy: unauth returns 401, citizen returns 403, responder succeeds', async () => {
      const triggerRes = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      assert.equal(triggerRes.status, 201);
      const sosId = triggerRes.body.data.id;

      // 1. Unauthenticated -> 401
      const unauthRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        body: { notes: 'Unauthenticated attempt' }
      });
      assert.equal(unauthRes.status, 401);
      assert.equal(unauthRes.body.error.code, 'UNAUTHORIZED_RESOLVE');

      // 2. Standard citizen -> 403
      const citizen = createTestToken({ role: 'citizen' });
      const citizenRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${citizen.token}` },
        body: { notes: 'Citizen attempt' }
      });
      assert.equal(citizenRes.status, 403);
      assert.equal(citizenRes.body.error.code, 'FORBIDDEN_RESOLVE');

      // 3. Responder -> 200 OK
      const responder = createTestToken({ role: 'first_responder' });
      const responderRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${responder.token}` },
        body: { notes: 'Responder attempt' }
      });
      assert.equal(responderRes.status, 200);
      assert.equal(responderRes.body.data.status, 'resolved');
    });

    it('anonymous alert resolve: valid resolveToken succeeds without auth, wrong token rejected, token not leaked', async () => {
      const triggerRes = await serverHarness.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090, alertType: 'CRITICAL_SOS' }
      });
      assert.equal(triggerRes.status, 201);
      const sosId = triggerRes.body.data.id;
      const resolveToken = triggerRes.body.data.resolveToken || triggerRes.body.resolveToken;
      assert.ok(resolveToken, 'trigger response must return a resolveToken');

      // Token must not leak through read endpoints
      const activeRes = await serverHarness.request('/api/v1/sos/active');
      const pub = activeRes.body.data.find(a => a.id === sosId);
      assert.ok(pub);
      assert.equal(pub.resolveToken, undefined);
      assert.equal(pub.resolveTokenHash, undefined);

      // Wrong token -> 401
      const badRes = await serverHarness.request('/api/v1/sos/' + sosId + '/resolve', {
        method: 'POST',
        body: { resolveToken: 'wrong-token-value' }
      });
      assert.equal(badRes.status, 401);

      // Correct token, no auth -> 200
      const okRes = await serverHarness.request('/api/v1/sos/' + sosId + '/resolve', {
        method: 'POST',
        body: { resolveToken, notes: 'I am safe now' }
      });
      assert.equal(okRes.status, 200);
      assert.equal(okRes.body.data.status, 'resolved');
    });
  });
});
