/**
/**
 * SafeSphere Milestone 2 - Empirical Adversarial Verification Suite
 * Author: Challenger 2 (teamwork_preview_challenger_m2_2_gen2)
 *
 * Verifies:
 * 1. Server runtime & Health Check endpoint (/health, /, 404)
 * 2. Real-time WebSocket Protocol (/ws/sos): Handshake, Heartbeat, Telemetry broadcast, Malformed JSON
 * 3. Community Incident Reports API (/api/v1/reports): Listing, filtering, validation, creation, XSS/Unicode
 * 4. Safety Markers & Haversine Distance (/api/v1/markers): Mathematical accuracy, sorting, radius boundaries
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { WebSocket } = require('ws');

const { app } = require('../src/app');
const { server, wss, broadcastSosAlert } = require('../src/server');
const { db } = require('../src/data/store');
const { calculateDistance, findNearby } = require('../src/services/geoService');
const { signAccessToken } = require('../src/services/tokenService');

describe('Milestone 2 Adversarial Verification - Server, WebSocket, Reports & Markers', () => {
  let testServer;
  let baseUrl;
  let wsUrl;
  let testPort;

  before(async () => {
    // Boot the composite server on ephemeral port (0)
    await new Promise((resolve, reject) => {
      server.listen(0, '127.0.0.1', (err) => {
        if (err) return reject(err);
        resolve();
      });
    });

    testPort = server.address().port;
    baseUrl = `http://127.0.0.1:${testPort}`;
    wsUrl = `ws://127.0.0.1:${testPort}/ws/sos`;
  });

  after(async () => {
    // Cleanly close WebSocket server and HTTP server
    await new Promise((resolve) => {
      wss.close(() => {
        server.close(resolve);
      });
    });
  });

  beforeEach(() => {
    db.reset();
  });

  // Helper HTTP request function
  async function apiRequest(path, options = {}) {
    const url = `${baseUrl}${path}`;
    const headers = {
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };

    const response = await fetch(url, {
      method: options.method || 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined
    });

    let jsonBody = null;
    try {
      jsonBody = await response.json();
    } catch (e) {
      jsonBody = null;
    }

    return {
      status: response.status,
      headers: response.headers,
      body: jsonBody
    };
  }

  // ===========================================================================
  // SECTION 1: Server Runtime, Health Check & Root Endpoints
  // ===========================================================================
  describe('1. Server Runtime & Health Check Endpoints', () => {
    it('returns 200 OK with healthy status, version, and uptime on /health', async () => {
      const res = await apiRequest('/health');

      assert.equal(res.status, 200);
      assert.ok(res.body);
      assert.equal(res.body.status, 'healthy');
      assert.equal(res.body.service, 'safesphere-backend');
      assert.equal(res.body.version, '1.0.0');
      assert.ok(typeof res.body.uptimeSeconds === 'number');
      assert.ok(res.body.uptimeSeconds >= 0);
      assert.ok(!isNaN(Date.parse(res.body.timestamp)));
    });

    it('returns 200 OK with API service metadata on /', async () => {
      const res = await apiRequest('/');

      assert.equal(res.status, 200);
      assert.ok(res.body);
      assert.equal(res.body.name, 'SafeSphere API Service');
      assert.equal(res.body.status, 'operational');
      assert.equal(res.body.apiRoot, '/api/v1');
    });

    it('returns 200 OK with endpoint index on /api/v1', async () => {
      const res = await apiRequest('/api/v1');

      assert.equal(res.status, 200);
      assert.ok(res.body);
      assert.equal(res.body.status, 'ok');
      assert.equal(res.body.endpoints.reports, '/api/v1/reports');
      assert.equal(res.body.endpoints.markers, '/api/v1/markers');
    });

    it('returns normalized 404 NOT_FOUND envelope for non-existent routes', async () => {
      const res = await apiRequest('/api/v1/unknown-endpoint-xyz');

      assert.equal(res.status, 404);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'NOT_FOUND');
    });
  });

  // ===========================================================================
  // SECTION 2: Real-Time WebSocket Protocol (/ws/sos)
  // ===========================================================================
  describe('2. Real-Time WebSocket Channel (/ws/sos)', () => {
    it('establishes connection and receives CONNECTION_ESTABLISHED welcome packet', async () => {
      const client = new WebSocket(wsUrl);

      const welcomeMsg = await new Promise((resolve, reject) => {
        client.on('message', (data) => {
          try {
            resolve(JSON.parse(data.toString()));
          } catch (e) {
            reject(e);
          }
        });
        client.on('error', reject);
      });

      assert.equal(welcomeMsg.type, 'CONNECTION_ESTABLISHED');
      assert.ok(welcomeMsg.message.includes('SafeSphere SOS'));
      assert.ok(welcomeMsg.timestamp);

      client.close();
    });

    it('responds with PONG to client PING heartbeat', async () => {
      const client = new WebSocket(wsUrl);

      // Wait for welcome message first
      await new Promise((resolve) => client.once('message', resolve));

      // Send PING
      client.send(JSON.stringify({ type: 'PING' }));

      const pongMsg = await new Promise((resolve) => {
        client.once('message', (data) => {
          resolve(JSON.parse(data.toString()));
        });
      });

      assert.equal(pongMsg.type, 'PONG');
      assert.ok(typeof pongMsg.timestamp === 'number');

      client.close();
    });

    it('gracefully handles malformed JSON without crashing the server', async () => {
      const client = new WebSocket(wsUrl);
      await new Promise((resolve) => client.once('message', resolve));

      // Send invalid JSON text
      client.send('{ bad json: true, missing quotes }');

      const errMsg = await new Promise((resolve) => {
        client.once('message', (data) => {
          resolve(JSON.parse(data.toString()));
        });
      });

      assert.equal(errMsg.type, 'ERROR');
      assert.equal(errMsg.message, 'Malformed JSON payload');

      // Verify server remains alive and responsive after error
      const healthRes = await apiRequest('/health');
      assert.equal(healthRes.status, 200);

      client.close();
    });

    it('broadcasts SOS_TELEMETRY to other connected clients without echoing back to sender', async () => {
      const clientSender = new WebSocket(wsUrl);
      const clientReceiver1 = new WebSocket(wsUrl);
      const clientReceiver2 = new WebSocket(wsUrl);

      // Wait for all 3 to receive welcome packets
      await Promise.all([
        new Promise((resolve) => clientSender.once('message', resolve)),
        new Promise((resolve) => clientReceiver1.once('message', resolve)),
        new Promise((resolve) => clientReceiver2.once('message', resolve))
      ]);

      const telemetryPayload = {
        type: 'SOS_TELEMETRY',
        sosId: 'sos_test_telemetry_01',
        latitude: 28.6315,
        longitude: 77.2167,
        battery: 85
      };

      // Set up listeners on receivers
      const recvPromise1 = new Promise((resolve) => {
        clientReceiver1.once('message', (data) => resolve(JSON.parse(data.toString())));
      });
      const recvPromise2 = new Promise((resolve) => {
        clientReceiver2.once('message', (data) => resolve(JSON.parse(data.toString())));
      });

      let senderEchoed = false;
      clientSender.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.sosId === 'sos_test_telemetry_01') {
          senderEchoed = true;
        }
      });

      // Send telemetry from clientSender
      clientSender.send(JSON.stringify(telemetryPayload));

      const [received1, received2] = await Promise.all([recvPromise1, recvPromise2]);

      // Both receivers got the broadcast
      assert.equal(received1.type, 'SOS_TELEMETRY');
      assert.equal(received1.sosId, 'sos_test_telemetry_01');
      assert.ok(received1.relayedAt, 'Expected relayedAt timestamp added by server');

      assert.equal(received2.type, 'SOS_TELEMETRY');
      assert.equal(received2.sosId, 'sos_test_telemetry_01');

      // Sender must NOT receive echo
      assert.equal(senderEchoed, false, 'Sender should not receive echo of its own telemetry');

      clientSender.close();
      clientReceiver1.close();
      clientReceiver2.close();
    });

    it('supports broadcastSosAlert helper pushing SOS_ALERT_BROADCAST to all connected clients', async () => {
      const client1 = new WebSocket(wsUrl);
      const client2 = new WebSocket(wsUrl);

      await Promise.all([
        new Promise((resolve) => client1.once('message', resolve)),
        new Promise((resolve) => client2.once('message', resolve))
      ]);

      const alertPayload = {
        id: 'sos_broadcast_99',
        status: 'active',
        alertType: 'CRITICAL_SOS',
        location: { latitude: 28.6, longitude: 77.2 }
      };

      const msgPromise1 = new Promise((resolve) => {
        client1.once('message', (data) => resolve(JSON.parse(data.toString())));
      });
      const msgPromise2 = new Promise((resolve) => {
        client2.once('message', (data) => resolve(JSON.parse(data.toString())));
      });

      // Invoke server-side broadcastSosAlert
      broadcastSosAlert(alertPayload);

      const [msg1, msg2] = await Promise.all([msgPromise1, msgPromise2]);

      assert.equal(msg1.type, 'SOS_ALERT_BROADCAST');
      assert.equal(msg1.data.id, 'sos_broadcast_99');
      assert.ok(msg1.timestamp);

      assert.equal(msg2.type, 'SOS_ALERT_BROADCAST');
      assert.equal(msg2.data.id, 'sos_broadcast_99');

      client1.close();
      client2.close();
    });

    it('survives rapid connection, messaging, and abrupt disconnection of 10 concurrent clients', async () => {
      const clientCount = 10;
      const clients = [];

      for (let i = 0; i < clientCount; i++) {
        const c = new WebSocket(wsUrl);
        clients.push(c);
      }

      // Wait for all connections to open
      await Promise.all(
        clients.map((c) => new Promise((resolve) => c.once('open', resolve)))
      );

      // Send random messages simultaneously
      clients.forEach((c, idx) => {
        c.send(JSON.stringify({ type: 'PING', id: idx }));
      });

      // Close all abruptly
      clients.forEach((c) => c.terminate());

      // Verify server is healthy and functioning
      const healthRes = await apiRequest('/health');
      assert.equal(healthRes.status, 200);
      assert.equal(healthRes.body.status, 'healthy');
    });
  });

  // ===========================================================================
  // SECTION 3: Community Incident Reports API (/api/v1/reports)
  // ===========================================================================
  describe('3. Incident Reports API (/api/v1/reports)', () => {
    it('lists seeded reports with pagination limit filter', async () => {
      const res = await apiRequest('/api/v1/reports?limit=2');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.count, 2);
      assert.equal(res.body.data.length, 2);
    });

    it('filters incident reports by type and status', async () => {
      const res = await apiRequest('/api/v1/reports?type=Theft&status=verified');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.length >= 1);
      for (const r of res.body.data) {
        assert.equal(r.type, 'Theft');
        assert.equal(r.status, 'verified');
      }
    });

    it('retrieves an existing report by ID', async () => {
      const res = await apiRequest('/api/v1/reports/rep_1001');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.id, 'rep_1001');
      assert.equal(res.body.data.type, 'Theft');
    });

    it('returns 404 REPORT_NOT_FOUND when requesting a non-existent report ID', async () => {
      const res = await apiRequest('/api/v1/reports/rep_non_existent_9999');

      assert.equal(res.status, 404);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'REPORT_NOT_FOUND');
    });

    it('creates a report anonymously when unauthenticated', async () => {
      const payload = {
        type: 'Suspicious',
        description: 'Broken street lamp creating a blind corner',
        location: 'Khel Gaon Marg Near Gate 3',
        latitude: 28.555,
        longitude: 77.222
      };

      const res = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.type, 'Suspicious');
      assert.equal(res.body.data.reportedBy, null);
      assert.ok(res.body.data.id);
    });

    it('associates report with user ID when valid Bearer token is provided', async () => {
      const demoUser = db.findUserByEmail('demo@safesphere.org');
      const token = signAccessToken(demoUser);

      const payload = {
        type: 'Accident',
        description: 'Road barrier damaged and protruding into lane',
        location: 'Barakhamba Road',
        latitude: 28.629,
        longitude: 77.228
      };

      const res = await apiRequest('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.reportedBy, 'user_safesphere_demo_01');
    });

    it('rejects report when description or location is missing or empty whitespace', async () => {
      // Missing description
      const res1 = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: { type: 'Theft', location: 'Market' }
      });
      assert.equal(res1.status, 400);
      assert.equal(res1.body.error.code, 'VALIDATION_ERROR');

      // Empty whitespace description
      const res2 = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: { description: '   ', location: 'Market' }
      });
      assert.equal(res2.status, 400);

      // Missing location
      const res3 = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: { description: 'Someone running away' }
      });
      assert.equal(res3.status, 400);
    });

    it('handles adversarial strings: XSS vectors, SQL injections, and multi-byte Unicode', async () => {
      const payload = {
        type: 'Other',
        description: "<script>alert('xss')</script> -- \"; DROP TABLE reports; -- 🚨⚠️ सुरक्षित क्षेत्र",
        location: '🗺️ Locus: 28°37\'48"N 77°13\'01"E — 蓮花寺',
        latitude: 28.5535,
        longitude: 77.2588
      };

      const res = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.description.includes('सुरक्षित क्षेत्र'));
      assert.ok(res.body.data.location.includes('蓮花寺'));
    });

    it('normalizes unrecognized report type to "Other"', async () => {
      const payload = {
        type: 'UNRECOGNIZED_WEIRD_CATEGORY_123',
        description: 'Odd sound reported near alleyway',
        location: 'Alley 4'
      };

      const res = await apiRequest('/api/v1/reports', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.data.type, 'Other');
    });
  });

  // ===========================================================================
  // SECTION 4: Safety Markers & Haversine Distance Engine
  // ===========================================================================
  describe('4. Safety Markers & Haversine Great-Circle Proximity Engine', () => {
    it('verifies mathematical precision of Haversine formula against theoretical distances', () => {
      // 1. Same point distance must be 0
      const distZero = calculateDistance(28.6315, 77.2167, 28.6315, 77.2167);
      assert.equal(distZero, 0);

      // 2. Connaught Place to AIIMS Hospital
      // CP: (28.6315, 77.2167)
      // AIIMS: (28.5672, 77.2100)
      // Theoretical great-circle distance is approx 7.18 km
      const cpToAiims = calculateDistance(28.6315, 77.2167, 28.5672, 77.2100);
      assert.ok(cpToAiims >= 7.10 && cpToAiims <= 7.25, `Expected ~7.18 km, got ${cpToAiims}`);

      // 3. Equator to North Pole (lat 0 to lat 90): ~10,007 km (1/4 of earth circumference)
      const poleDist = calculateDistance(0, 0, 90, 0);
      assert.ok(poleDist >= 10000 && poleDist <= 10015, `Expected ~10,007 km, got ${poleDist}`);

      // 4. Antipodal points (0, 0) to (0, 180): ~20,015 km (half circumference)
      const antipodalDist = calculateDistance(0, 0, 0, 180);
      assert.ok(antipodalDist >= 20000 && antipodalDist <= 20020, `Expected ~20,015 km, got ${antipodalDist}`);
    });

    it('lists all seeded safety markers', async () => {
      const res = await apiRequest('/api/v1/markers');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.length >= 3);
    });

    it('filters markers by category and verification flag', async () => {
      const res = await apiRequest('/api/v1/markers?category=Hospital&isVerified=true');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.length >= 1);
      for (const m of res.body.data) {
        assert.equal(m.category, 'Hospital');
        assert.equal(m.isVerified, true);
      }
    });

    it('retrieves safety marker by ID', async () => {
      const res = await apiRequest('/api/v1/markers/marker_police_cp');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.name, 'Connaught Place Central Police Post');
    });

    it('returns 404 MARKER_NOT_FOUND when requesting non-existent marker ID', async () => {
      const res = await apiRequest('/api/v1/markers/marker_non_existent_xyz');

      assert.equal(res.status, 404);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'MARKER_NOT_FOUND');
    });

    it('returns 400 MISSING_COORDINATES on /api/v1/markers/nearby when coords are omitted', async () => {
      const res = await apiRequest('/api/v1/markers/nearby');

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'MISSING_COORDINATES');
    });

    it('performs strict Haversine proximity filtering with small radius (1km)', async () => {
      // Query centered directly on Connaught Place Police Post (28.6315, 77.2167) with radius 1km
      const res = await apiRequest('/api/v1/markers/nearby?lat=28.6315&lon=77.2167&radius=1');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);

      // Only Connaught Place police station is within 1 km; AIIMS (7.18 km) must be excluded
      const names = res.body.data.map((m) => m.name);
      assert.ok(names.includes('Connaught Place Central Police Post'));
      assert.ok(!names.includes('AIIMS Emergency Trauma Care'));

      for (const m of res.body.data) {
        assert.ok(m.distanceKm <= 1.0);
      }
    });

    it('includes farther facilities when radius is expanded to 10km and guarantees ascending distance sort', async () => {
      const res = await apiRequest('/api/v1/markers/nearby?lat=28.6315&lon=77.2167&radius=10');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.length >= 3);

      const names = res.body.data.map((m) => m.name);
      assert.ok(names.includes('AIIMS Emergency Trauma Care'));

      // Ascending distance check
      for (let i = 0; i < res.body.data.length - 1; i++) {
        assert.ok(
          res.body.data[i].distanceKm <= res.body.data[i + 1].distanceKm,
          `Markers must be strictly sorted by proximity: ${res.body.data[i].distanceKm} <= ${res.body.data[i + 1].distanceKm}`
        );
      }
    });

    it('supports alias query parameters: lat/lon vs latitude/longitude', async () => {
      const res1 = await apiRequest('/api/v1/markers?lat=28.6315&lon=77.2167&radius=5');
      const res2 = await apiRequest('/api/v1/markers?latitude=28.6315&longitude=77.2167&radius=5');

      assert.equal(res1.status, 200);
      assert.equal(res2.status, 200);
      assert.equal(res1.body.count, res2.body.count);
    });

    it('handles non-numeric coordinate inputs gracefully without throwing 500', async () => {
      const res = await apiRequest('/api/v1/markers/nearby?lat=invalid_latitude&lon=invalid_longitude');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.count, 0);
      assert.deepEqual(res.body.data, []);
    });

    it('creates a new verified safety marker with POST /api/v1/markers returning 201 Created', async () => {
      const newMarker = {
        name: 'Hauz Khas 24/7 Police Assistance Booth',
        category: 'Police Station',
        latitude: 28.5494,
        longitude: 77.2001,
        address: 'Hauz Khas Village Entrance',
        isVerified: true
      };

      const res = await apiRequest('/api/v1/markers', {
        method: 'POST',
        body: newMarker
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.name, 'Hauz Khas 24/7 Police Assistance Booth');
      assert.ok(res.body.data.id.startsWith('marker_'));

      // Verify newly created marker is discoverable via proximity search
      const nearRes = await apiRequest('/api/v1/markers/nearby?lat=28.5494&lon=77.2001&radius=1');
      assert.equal(nearRes.status, 200);
      const found = nearRes.body.data.find((m) => m.name === 'Hauz Khas 24/7 Police Assistance Booth');
      assert.ok(found);
      assert.equal(found.distanceKm, 0);
    });

    it('rejects marker creation when required fields (name, lat, lon) are missing returning 400', async () => {
      const res = await apiRequest('/api/v1/markers', {
        method: 'POST',
        body: { category: 'Hospital' }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });
  });
});
