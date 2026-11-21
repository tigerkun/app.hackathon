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

      const { token: m2Token } = createTestToken();
      const res = await serverHarness.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${m2Token}` },
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.type, 'Theft');
      assert.equal(res.body.data.status, 'pending');
      assert.ok(res.body.data.id.startsWith('rep_'));
    });

    it('rejects report submission with missing description with 400 Bad Request', async () => {
      const { token: m2Token2 } = createTestToken();
      const res = await serverHarness.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${m2Token2}` },
        body: { location: 'Connaught Place' }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('manages report status lifecycle via POST /api/v1/reports/:id/status (privileged only)', async () => {
      // Create a test report
      const { token: m2Token3 } = createTestToken();
      const repRes = await serverHarness.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${m2Token3}` },
        body: {
          type: 'Theft',
          description: 'Wallet stolen from café table',
          location: 'Khan Market',
          latitude: 28.6000,
          longitude: 77.2270
        }
      });
      assert.equal(repRes.status, 201);
      const reportId = repRes.body.data.id;
      assert.equal(repRes.body.data.status, 'pending');

      // 1. Unauthenticated attempt
      const unauth = await serverHarness.request(`/api/v1/reports/${reportId}/status`, {
        method: 'POST',
        body: { status: 'verified' }
      });
      assert.equal(unauth.status, 401);

      // 2. Citizen attempt (unprivileged)
      const citizen = createTestToken({ role: 'citizen' });
      const citizenRes = await serverHarness.request(`/api/v1/reports/${reportId}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${citizen.token}` },
        body: { status: 'verified' }
      });
      assert.equal(citizenRes.status, 403);

      // 3. Admin updates to verified
      const admin = createTestToken({ role: 'admin' });
      const adminRes = await serverHarness.request(`/api/v1/reports/${reportId}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${admin.token}` },
        body: { status: 'verified' }
      });
      assert.equal(adminRes.status, 200);
      assert.equal(adminRes.body.data.status, 'verified');

      // 4. Responder updates to resolved
      const responder = createTestToken({ role: 'responder' });
      const resolveRes = await serverHarness.request(`/api/v1/reports/${reportId}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${responder.token}` },
        body: { status: 'resolved' }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');

      // 5. Invalid status returns 400
      const invalidRes = await serverHarness.request(`/api/v1/reports/${reportId}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${admin.token}` },
        body: { status: 'invalid_status_xyz' }
      });
      assert.equal(invalidRes.status, 400);

      // 6. Non-existent report returns 404
      const nonExistent = await serverHarness.request('/api/v1/reports/rep_non_existent/status', {
        method: 'POST',
        headers: { Authorization: `Bearer ${admin.token}` },
        body: { status: 'rejected' }
      });
      assert.equal(nonExistent.status, 404);
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

    it('M4: accepts the 24x7 Store category (always-open refuge) verbatim', async () => {
      const { createMarker } = require('../src/models/markerModel');
      const marker = createMarker({
        name: 'Night Owl Mini Mart',
        category: '24x7 Store',
        latitude: 28.61,
        longitude: 77.21,
        isVerified: true
      });
      assert.equal(marker.category, '24x7 Store', '24x7 Store must pass validation verbatim');

      // Unknown categories still fall back to Verified Safe Zone
      const fallback = createMarker({
        name: 'Weird Category',
        category: 'Not A Real Category',
        latitude: 28.61,
        longitude: 77.21
      });
      assert.equal(fallback.category, 'Verified Safe Zone');
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

    it('requires privileged auth (admin/responder) for GET /api/v1/markers/pending', async () => {
      // 1. Unauthenticated request
      const unauth = await serverHarness.request('/api/v1/markers/pending');
      assert.equal(unauth.status, 401);

      // 2. Citizen request
      const citizen = createTestToken({ role: 'citizen' });
      const citizenRes = await serverHarness.request('/api/v1/markers/pending', {
        headers: { Authorization: `Bearer ${citizen.token}` }
      });
      assert.equal(citizenRes.status, 403);

      // 3. Admin request
      const admin = createTestToken({ role: 'admin' });
      const adminRes = await serverHarness.request('/api/v1/markers/pending', {
        headers: { Authorization: `Bearer ${admin.token}` }
      });
      assert.equal(adminRes.status, 200);
      assert.ok(Array.isArray(adminRes.body.data));
    });

    it('allows admin/responder to verify or reject pending markers with audit logging', async () => {
      // Create an unverified marker first
      const citizen = createTestToken({ role: 'citizen' });
      const createdRes = await serverHarness.request('/api/v1/markers', {
        method: 'POST',
        headers: { Authorization: `Bearer ${citizen.token}` },
        body: {
          name: 'Underground Pedestrian Subway Guard Post',
          latitude: 28.6350,
          longitude: 77.2180,
          category: 'Verified Safe Zone'
        }
      });
      assert.equal(createdRes.status, 201);
      const markerId = createdRes.body.data.id;
      assert.equal(createdRes.body.data.isVerified, false);
      assert.equal(createdRes.body.data.status, 'pending');

      // Unauthenticated verify attempt
      const unauthVerify = await serverHarness.request(`/api/v1/markers/${markerId}/verify`, {
        method: 'POST',
        body: { approve: true }
      });
      assert.equal(unauthVerify.status, 401);

      // Citizen verify attempt
      const citizenVerify = await serverHarness.request(`/api/v1/markers/${markerId}/verify`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${citizen.token}` },
        body: { approve: true }
      });
      assert.equal(citizenVerify.status, 403);

      // Admin approves
      const admin = createTestToken({ role: 'admin', id: 'admin_test_1' });
      const approveRes = await serverHarness.request(`/api/v1/markers/${markerId}/verify`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${admin.token}` },
        body: { approve: true }
      });
      assert.equal(approveRes.status, 200);
      assert.equal(approveRes.body.data.isVerified, true);
      assert.equal(approveRes.body.data.status, 'verified');
      assert.ok(approveRes.body.data.verifiedBy);
      assert.ok(approveRes.body.data.verifiedAt);

      // Admin rejects a different unverified marker
      const secondCreated = await serverHarness.request('/api/v1/markers', {
        method: 'POST',
        body: {
          name: 'Vandalized Kiosk',
          latitude: 28.6360,
          longitude: 77.2190
        }
      });
      const rejectRes = await serverHarness.request(`/api/v1/markers/${secondCreated.body.data.id}/verify`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${admin.token}` },
        body: { approve: false }
      });
      assert.equal(rejectRes.status, 200);
      assert.equal(rejectRes.body.data.isVerified, false);
      assert.equal(rejectRes.body.data.status, 'rejected');

      // Verify rejected marker is completely excluded from public listings
      const publicList = await serverHarness.request('/api/v1/markers');
      assert.equal(publicList.status, 200);
      const hasRejected = publicList.body.data.some((m) => m.id === secondCreated.body.data.id);
      assert.equal(hasRejected, false, 'Rejected markers must never be returned to citizens on /markers');

      // Verify isVerified=true filter returns only verified markers
      const verifiedList = await serverHarness.request('/api/v1/markers?isVerified=true');
      assert.equal(verifiedList.status, 200);
      assert.ok(verifiedList.body.data.length > 0);
      assert.ok(verifiedList.body.data.every((m) => m.isVerified === true));
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
