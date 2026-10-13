/**
 * SafeSphere Reports, Markers, and SOS Integration Tests
 * Native Node.js test runner using node:test and node:assert/strict.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');

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

      // Resolve alert
      const resolveRes = await serverHarness.request(`/api/v1/sos/${sosId}/resolve`, {
        method: 'POST',
        body: { notes: 'Citizen reported safe by responder team' }
      });
      assert.equal(resolveRes.status, 200);
      assert.equal(resolveRes.body.data.status, 'resolved');
      assert.ok(resolveRes.body.data.resolvedAt);
    });
  });
});
