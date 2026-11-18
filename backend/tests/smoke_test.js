/**
 * SafeSphere Production API Smoke Test Suite
 * 
 * Verifies live HTTP endpoints against local test server or remote deployed instance.
 * Covers:
 * 1. Health & Liveness probes (/healthz, /health)
 * 2. Auth lifecycle (Registration, Login)
 * 3. Emergency SOS lifecycle (Trigger, Capture resolveToken, 401 Invalid Token, 200 Valid Token Resolve)
 * 4. Location Tracking lifecycle (Share session, GET Track with token, Ping breadcrumb, Terminate)
 * 
 * Usage:
 *   node backend/tests/smoke_test.js
 *   BASE_URL=https://safesphere.onrender.com node backend/tests/smoke_test.js
 *   node backend/tests/smoke_test.js https://safesphere.onrender.com
 */

const http = require('http');
const assert = require('assert');

// If BASE_URL is set, test remote instance; otherwise boot isolated local server
const targetUrl = process.env.BASE_URL || process.argv[2] || null;

async function runSmokeTests() {
  console.log('================================================================');
  console.log('  SafeSphere API Live Smoke Test Suite');
  console.log(`  Timestamp: ${new Date().toISOString()}`);
  console.log('================================================================\n');

  let serverInstance = null;
  let baseUrl = targetUrl;

  if (!baseUrl) {
    console.log('[Setup] No BASE_URL provided — booting local test server harness...');
    const { startTestServer } = require('./helpers/testApp');
    serverInstance = await startTestServer();
    baseUrl = serverInstance.baseUrl;
    console.log(`[Setup] Local test server running on ${baseUrl}\n`);
  } else {
    console.log(`[Setup] Testing remote target: ${baseUrl}\n`);
  }

  // Helper fetcher
  async function api(path, options = {}) {
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
    } catch (_) {
      body = null;
    }
    return { status: res.status, headers: res.headers, body };
  }

  let passedTests = 0;
  let totalTests = 0;

  function recordPass(testName, details) {
    passedTests++;
    totalTests++;
    console.log(`  [PASS] ${testName}`);
    if (details) {
      console.log(`         -> ${details}`);
    }
  }

  function recordFail(testName, error) {
    totalTests++;
    console.error(`  [FAIL] ${testName}:`, error);
    throw error;
  }

  try {
    // =========================================================================
    // 1. Health & Liveness Probes
    // =========================================================================
    console.log('--- Phase 1: Health & Telemetry Probes ---');

    // 1.1 GET /healthz
    {
      const res = await api('/healthz');
      assert.strictEqual(res.status, 200, `Expected 200 OK from /healthz, got ${res.status}`);
      assert.strictEqual(res.body?.status, 'ok', `Expected status "ok", got ${JSON.stringify(res.body)}`);
      recordPass('GET /healthz returns 200 OK with status: "ok"', `status=${res.body.status}`);
    }

    // 1.2 GET /health
    {
      const res = await api('/health');
      assert.strictEqual(res.status, 200, `Expected 200 OK from /health, got ${res.status}`);
      assert.strictEqual(res.body?.status, 'healthy', `Expected healthy status, got ${res.body?.status}`);
      
      // Verify db: "ok" (or database: "OK")
      const dbStatus = res.body?.db || res.body?.database || res.body?.databaseStatus;
      assert.ok(dbStatus && dbStatus.toLowerCase() === 'ok', `Expected database status "ok", got ${dbStatus}`);

      // Verify wsClients
      const wsCount = res.body?.wsClients !== undefined ? res.body.wsClients : res.body?.wsClientCount;
      assert.strictEqual(typeof wsCount, 'number', `Expected numeric wsClients, got ${typeof wsCount}`);

      // Verify uptime
      assert.strictEqual(typeof res.body?.uptime, 'number', `Expected numeric uptime, got ${typeof res.body?.uptime}`);

      // Verify isProduction
      assert.strictEqual(typeof res.body?.isProduction, 'boolean', `Expected boolean isProduction, got ${typeof res.body?.isProduction}`);

      recordPass(
        'GET /health returns db: "ok", wsClients, uptime, and isProduction',
        `db=${dbStatus}, wsClients=${wsCount}, uptime=${res.body.uptime.toFixed(2)}s, isProduction=${res.body.isProduction}`
      );
    }

    // =========================================================================
    // 2. Authentication Lifecycle
    // =========================================================================
    console.log('\n--- Phase 2: User Authentication Lifecycle ---');

    const testEmail = `smoke_${Date.now()}@safesphere.test`;
    const testPhone = `+9199${Math.floor(10000000 + Math.random() * 90000000)}`;
    const testPassword = 'SmokePassword2026!';
    let authToken = null;
    let userId = null;

    // 2.1 Register User
    {
      const res = await api('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Smoke Test Citizen',
          email: testEmail,
          phone: testPhone,
          password: testPassword,
          pin: '1234',
          emergencyContact: {
            name: 'Emergency Guardian',
            phone: '+919876543210',
            relationship: 'Family'
          }
        }
      });
      assert.strictEqual(res.status, 201, `Expected 201 from registration, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      assert.ok(res.body?.data?.accessToken, 'Expected accessToken in registration response');
      userId = res.body.data.user.id;
      recordPass('POST /api/v1/auth/register creates user and issues JWT tokens', `userId=${userId}, email=${testEmail}`);
    }

    // 2.2 Login User
    {
      const res = await api('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: testEmail,
          password: testPassword
        }
      });
      assert.strictEqual(res.status, 200, `Expected 200 from login, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      authToken = res.body?.data?.accessToken;
      assert.ok(authToken, 'Expected accessToken in login response');
      recordPass('POST /api/v1/auth/login authenticates user and yields access token', `tokenLength=${authToken.length}`);
    }

    // =========================================================================
    // 3. Emergency SOS Lifecycle & resolveToken Self-Resolve
    // =========================================================================
    console.log('\n--- Phase 3: SOS Lifecycle & resolveToken Self-Resolve ---');

    let sosAlertId = null;
    let resolveToken = null;

    // 3.1 Trigger Anonymous SOS
    {
      const res = await api('/api/v1/sos/trigger', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          accuracy: 5.2,
          batteryLevel: 85,
          alertType: 'CRITICAL_SOS',
          notes: 'Smoke test urgent distress trigger'
        }
      });
      assert.strictEqual(res.status, 201, `Expected 201 Created from SOS trigger, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);

      sosAlertId = res.body?.data?.id || res.body?.id;
      resolveToken = res.body?.data?.resolveToken || res.body?.resolveToken;

      assert.ok(sosAlertId, 'Expected alertId in SOS response');
      assert.ok(resolveToken, 'Expected resolveToken in SOS response');
      assert.strictEqual(res.body?.data?.status, 'active');

      recordPass(
        'POST /api/v1/sos/trigger generates SOS and captures resolveToken',
        `alertId=${sosAlertId}, resolveToken=${resolveToken.slice(0, 10)}... (length=${resolveToken.length})`
      );
    }

    // 3.2 Attempt Self-Resolve with INVALID token -> Expect 401 UNAUTHORIZED_RESOLVE
    {
      const res = await api(`/api/v1/sos/${sosAlertId}/resolve`, {
        method: 'POST',
        body: {
          resolveToken: 'invalid_forged_resolve_token_xyz_99999',
          notes: 'Malicious unauthorized attempt'
        }
      });
      assert.strictEqual(res.status, 401, `Expected 401 Unauthorized for invalid token, got ${res.status}`);
      assert.strictEqual(res.body?.success, false);
      assert.strictEqual(
        res.body?.error?.code,
        'UNAUTHORIZED_RESOLVE',
        `Expected error code UNAUTHORIZED_RESOLVE, got ${res.body?.error?.code}`
      );
      recordPass(
        'POST /api/v1/sos/:id/resolve with INVALID token returns 401 UNAUTHORIZED_RESOLVE',
        `status=${res.status}, code=${res.body.error.code}`
      );
    }

    // 3.3 Self-Resolve with VALID resolveToken -> Expect 200 OK
    {
      const res = await api(`/api/v1/sos/${sosAlertId}/resolve`, {
        method: 'POST',
        body: {
          resolveToken: resolveToken,
          notes: 'Distress resolved by citizen safely'
        }
      });
      assert.strictEqual(res.status, 200, `Expected 200 OK for valid resolveToken, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      assert.strictEqual(res.body?.data?.status, 'resolved');
      assert.strictEqual(res.body?.data?.id, sosAlertId);
      recordPass(
        'POST /api/v1/sos/:id/resolve with VALID resolveToken returns 200 OK and marks alert resolved',
        `status=${res.status}, alertStatus=${res.body.data.status}`
      );
    }

    // =========================================================================
    // 4. Live Guardian Location Tracking Lifecycle
    // =========================================================================
    console.log('\n--- Phase 4: Location Tracking Lifecycle ---');

    let trackingSessionId = null;
    let trackingToken = null;

    // 4.1 Share Location Session
    {
      const res = await api('/api/v1/location/share-session', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          accuracy: 4.5,
          speed: 1.2,
          battery: 92,
          durationMinutes: 45,
          userName: 'Smoke Test Traveler'
        }
      });
      assert.strictEqual(res.status, 201, `Expected 201 Created from share-session, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);

      trackingSessionId = res.body?.sessionId;
      trackingToken = res.body?.token;

      assert.ok(trackingSessionId, 'Expected sessionId from share-session');
      assert.ok(trackingToken, 'Expected capability token from share-session');
      assert.ok(res.body?.shareUrl, 'Expected shareUrl in response');

      recordPass(
        'POST /api/v1/location/share-session creates tracking session & capability token',
        `sessionId=${trackingSessionId}, token=${trackingToken.slice(0, 10)}..., shareUrl=${res.body.shareUrl}`
      );
    }

    // 4.2 GET Track Endpoint with Token -> Expect 200 OK
    {
      const res = await api(`/api/v1/location/track/${trackingSessionId}?token=${trackingToken}`);
      assert.strictEqual(res.status, 200, `Expected 200 OK from GET track, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      assert.strictEqual(res.body?.data?.sessionId, trackingSessionId);
      assert.strictEqual(res.body?.data?.status, 'active');
      recordPass(
        'GET /api/v1/location/track/:sessionId with token returns 200 OK and session snapshot',
        `sessionId=${res.body.data.sessionId}, status=${res.body.data.status}`
      );
    }

    // 4.3 Breadcrumb Ping -> Expect 200 OK
    {
      const res = await api('/api/v1/location/ping', {
        method: 'POST',
        body: {
          sessionId: trackingSessionId,
          token: trackingToken,
          latitude: 28.6160,
          longitude: 77.2110,
          accuracy: 3.5,
          speed: 2.4,
          battery: 91
        }
      });
      assert.strictEqual(res.status, 200, `Expected 200 OK from location ping, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      const pointCount = res.body?.data?.pointCount !== undefined ? res.body.data.pointCount : res.body?.pointCount;
      assert.ok(pointCount >= 1, `Expected pointCount >= 1, got ${pointCount}`);
      recordPass(
        'POST /api/v1/location/ping records new breadcrumb and returns 200 OK',
        `pointCount=${pointCount}, currentLat=${res.body?.data?.currentLocation?.latitude}`
      );
    }

    // 4.4 Terminate Session -> Expect 200 OK
    {
      const res = await api(`/api/v1/location/terminate/${trackingSessionId}`, {
        method: 'POST',
        body: {
          token: trackingToken,
          reason: 'Smoke test destination reached safely'
        }
      });
      assert.strictEqual(res.status, 200, `Expected 200 OK from terminate, got ${res.status}`);
      assert.strictEqual(res.body?.success, true);
      assert.strictEqual(res.body?.data?.status, 'ended');
      recordPass(
        'POST /api/v1/location/terminate/:sessionId successfully terminates session',
        `sessionId=${res.body?.data?.id || res.body?.data?.sessionId || trackingSessionId}, status=${res.body?.data?.status}`
      );
    }

    console.log('\n================================================================');
    console.log(`  All ${passedTests}/${totalTests} Smoke Tests PASSED Successfully!`);
    console.log('================================================================\n');

  } catch (err) {
    console.error('\n================================================================');
    console.error('  Smoke Test Suite FAILED:');
    console.error(err);
    console.error('================================================================\n');
    process.exitCode = 1;
  } finally {
    if (serverInstance) {
      await serverInstance.close();
      console.log('[Teardown] Local test server stopped cleanly.');
    }
  }
}

// Execute suite
runSmokeTests();
