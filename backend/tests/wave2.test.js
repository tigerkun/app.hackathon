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
    it('returns text/html 200 on GET /?session=trk_test&token=tok_test', async () => {
      const res = await fetch(`${baseUrl}/?session=trk_test&token=tok_test`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'), 'HTML title missing');
      assert.ok(body.includes('#0B0F1A'), 'Dark background color missing');
      assert.ok(body.includes('textContent'), 'Script must use textContent for XSS safety');
      assert.ok(!body.includes('innerHTML'), 'Script must NOT use innerHTML');
    });

    it('returns text/html 200 on GET /track', async () => {
      const res = await fetch(`${baseUrl}/track`);
      assert.equal(res.status, 200);
      const contentType = res.headers.get('content-type') || '';
      assert.ok(contentType.includes('text/html'), `Expected text/html, got ${contentType}`);
      const body = await res.text();
      assert.ok(body.includes('SafeSphere — Live Guardian Tracking'));
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
  });
});
