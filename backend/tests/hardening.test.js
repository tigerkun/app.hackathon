/**
 * Deferred Hardening Wave Test Suite
 *
 * Verifies the audit-report fixes:
 * 1. Guest SOS identity stripping — body userId/userName/userPhone are ignored
 *    for unauthenticated triggers (impersonation guard), and alerts carry the
 *    anonymous identity instead.
 * 2. optionalAuth revocation check — a token whose session was invalidated
 *    (logout) degrades to guest on optionalAuth routes, instead of retaining
 *    identity until JWT expiry.
 * 3. requireAuth missing-session gate — an access token whose session row is
 *    gone is rejected with SESSION_REVOKED, never silently accepted.
 * 4. Input length limits — SOS notes/alertType caps, report description/location
 *    caps, report latitude/longitude validation, and direct photoUrl rejection.
 * 5. OTP limiter middleware behavior (429 after max requests per window).
 * 6. Env fail-closed — an unknown NODE_ENV value boots with production-level
 *    JWT secret enforcement (spawnSync child: no secrets → refuses to load).
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');
const bcrypt = require('bcryptjs');

const { startTestServer } = require('./helpers/testApp');
const { createRateLimiter } = require('../src/middleware/rateLimiter');
const { createUser } = require('../src/models/userModel');
const { db } = require('../src/data/store');

function makeUser(store, name) {
  return store.saveUser(createUser({
    name,
    email: `${name.toLowerCase().replace(/\s+/g, '.')}.hardening@safesphere.test`,
    phone: `+9188${String(Math.floor(Math.random() * 1e8)).padStart(8, '0')}`,
    passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
    phoneVerified: true
  }));
}

describe('Hardening Wave', () => {
  let t;

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();
  });

  after(async () => {
    await t.close();
  });

  describe('1+2. Guest SOS identity stripping & optionalAuth revocation', () => {
    let victim;
    let victimToken;

    before(async () => {
      victim = makeUser(db, 'Impersonation Victim');
      const res = await t.request('/api/v1/auth/login', {
        method: 'POST',
        body: { emailOrPhone: victim.email, password: 'Str0ngPass!23' }
      });
      assert.equal(res.status, 200);
      victimToken = res.body.data.accessToken;
    });

    it('strips client-supplied identity for guest SOS triggers', async () => {
      const res = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: {
          latitude: 28.61,
          longitude: 77.21,
          // Attacker declares the victim's identity — must be ignored:
          userId: victim.id,
          user_id: victim.id,
          userName: 'Impersonation Victim',
          userPhone: victim.phone
        }
      });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.userId, 'anonymous', 'guest alerts must be anonymous');
      assert.equal(res.body.data.userName, 'SafeSphere Citizen');
      assert.equal(res.body.data.userPhone, '');
      // Cleanup
      await t.request(`/api/v1/sos/${res.body.data.id}/resolve`, {
        method: 'POST',
        body: { notes: 'test cleanup' }
      });
    });

    it('keeps verified identity for authenticated SOS triggers', async () => {
      const res = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${victimToken}` },
        body: { latitude: 28.61, longitude: 77.21 }
      });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.userId, victim.id);
      assert.equal(res.body.data.userName, 'Impersonation Victim');
      await t.request(`/api/v1/sos/${res.body.data.id}/resolve`, {
        method: 'POST',
        body: { notes: 'test cleanup' }
      });
    });

    it('degrades revoked-session tokens to guest on optionalAuth routes', async () => {
      // Logout invalidates the session row behind the access token
      const logout = await t.request('/api/v1/auth/logout', {
        method: 'POST',
        headers: { Authorization: `Bearer ${victimToken}` },
        body: {}
      });
      assert.equal(logout.status, 200);

      // Re-login for requireAuth-path checks below
      const again = await t.request('/api/v1/auth/login', {
        method: 'POST',
        body: { emailOrPhone: victim.email, password: 'Str0ngPass!23' }
      });
      const freshToken = again.body.data.accessToken;

      // The old (revoked) token on an optionalAuth route must act as GUEST:
      // SOS trigger yields an anonymous alert, NOT one owned by the victim.
      const res = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${victimToken}` },
        body: { latitude: 28.61, longitude: 77.21 }
      });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.userId, 'anonymous', 'revoked token must not retain identity');
      await t.request(`/api/v1/sos/${res.body.data.id}/resolve`, {
        method: 'POST',
        body: { notes: 'test cleanup' }
      });

      // requireAuth path: revoked token on /auth/me must be rejected
      const me = await t.request('/api/v1/auth/me', {
        method: 'GET',
        headers: { Authorization: `Bearer ${victimToken}` }
      });
      assert.equal(me.status, 401);
      assert.equal(me.body.error.code, 'SESSION_REVOKED');

      // Sanity: the fresh token still authenticates
      const meFresh = await t.request('/api/v1/auth/me', {
        method: 'GET',
        headers: { Authorization: `Bearer ${freshToken}` }
      });
      assert.equal(meFresh.status, 200);
    });
  });

  describe('4. Input length limits', () => {
    let reportToken;

    before(async () => {
      db.saveUser(createUser({
        id: 'usr_m2_caps',
        name: 'Caps User',
        email: 'caps@safesphere.test',
        phone: '+918800200009',
        phoneVerified: true,
        passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
      }));
      const login = await t.request('/api/v1/auth/login', {
        method: 'POST',
        body: { emailOrPhone: 'caps@safesphere.test', password: 'Str0ngPass!23' }
      });
      reportToken = login.body.data.accessToken;
    });

    it('rejects SOS notes longer than 500 characters', async () => {
      const res = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.61, longitude: 77.21, notes: 'x'.repeat(501) }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
      assert.ok(res.body.error.details.some(d => d.field === 'notes'));
    });

    it('rejects SOS alertType longer than 40 characters', async () => {
      const res = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.61, longitude: 77.21, alertType: 'y'.repeat(41) }
      });
      assert.equal(res.status, 400);
      assert.ok(res.body.error.details.some(d => d.field === 'alertType'));
    });

    it('rejects direct photoUrl submission on reports (validation bypass)', async () => {
      const res = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${reportToken}` },
        body: {
          type: 'hazard',
          description: 'bypass attempt',
          location: 'test',
          photoUrl: 'data:text/html;base64,PGh0bWw+PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0PjwvaHRtbD4='
        }
      });
      assert.equal(res.status, 400);
      assert.ok(res.body.error.details.some(d => d.field === 'photoUrl'));
    });

    it('rejects report descriptions over 2000 characters', async () => {
      const res = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${reportToken}` },
        body: { type: 'hazard', description: 'z'.repeat(2001), location: 'test' }
      });
      assert.equal(res.status, 400);
      assert.ok(res.body.error.details.some(d => d.field === 'description'));
    });

    it('rejects report locations over 200 characters', async () => {
      const res = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${reportToken}` },
        body: { type: 'hazard', description: 'fine', location: 'l'.repeat(201) }
      });
      assert.equal(res.status, 400);
      assert.ok(res.body.error.details.some(d => d.field === 'location'));
    });

    it('rejects non-numeric report coordinates', async () => {
      for (const coords of [{ latitude: 'abc', longitude: 77.2 }, { latitude: 28.6, longitude: 'xyz' }]) {
        const res = await t.request('/api/v1/reports', {
          method: 'POST',
          headers: { Authorization: `Bearer ${reportToken}` },
          body: { type: 'hazard', description: 'coord check', location: 'test', ...coords }
        });
        assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(coords)}`);
      }
    });

    it('accepts valid report coordinates and photoBase64 flow', async () => {
      const res = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${reportToken}` },
        body: { type: 'hazard', description: 'coord ok', location: 'test', latitude: 28.61, longitude: 77.21 }
      });
      assert.equal(res.status, 201);
    });
  });

  describe('5. OTP limiter middleware behavior', () => {
    function fakeRes() {
      const out = { statusCode: 200, headers: {}, body: null };
      out.setHeader = (k, v) => { out.headers[k] = v; };
      out.status = (code) => { out.statusCode = code; return out; };
      out.json = (payload) => { out.body = payload; return out; };
      return out;
    }

    it('returns 429 with RATE_LIMIT_EXCEEDED after the per-window max', () => {
      const limiter = createRateLimiter({ windowMs: 60000, max: 2, skipInTest: false });
      const req = { ip: '203.0.113.9' };
      let passed = 0;
      limiter(req, fakeRes(), () => { passed++; });
      limiter(req, fakeRes(), () => { passed++; });
      assert.equal(passed, 2, 'first two requests must pass through');
      const thirdRes = fakeRes();
      limiter(req, thirdRes, () => { passed++; });
      assert.equal(passed, 2, 'next() must not fire for the limited request');
      assert.equal(thirdRes.statusCode, 429);
      assert.equal(thirdRes.body.error.code, 'RATE_LIMIT_EXCEEDED');
      assert.ok(Number(thirdRes.headers['Retry-After']) >= 1);
    });
  });

  describe('M1.6b: Forgot-PIN recovery (phone OTP → PIN reset)', () => {
    it('resets the PIN with a valid OTP and logs in with the new PIN', async () => {
      const email = 'pin.reset@safesphere.test';
      const phone = '+918811223344';
      const reg = await t.request('/api/v1/auth/register', {
        method: 'POST',
        body: { name: 'Pin Reset User', email, phone, password: 'Str0ngPass!23', pin: '1111' }
      });
      assert.equal(reg.status, 201);

      // Request OTP for the registered phone (test env returns devOtp)
      const send = await t.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone, purpose: 'login' }
      });
      assert.equal(send.status, 200);
      const devOtp = send.body.devOtp;
      assert.ok(devOtp, 'test env must surface devOtp');

      // Reset the PIN via the new endpoint
      const reset = await t.request('/api/v1/auth/pin/reset', {
        method: 'POST',
        body: { phone, otp: devOtp, newPin: '998877' }
      });
      assert.equal(reset.status, 200);
      assert.equal(reset.body.success, true);

      // Old PIN must now fail; new PIN must succeed
      const oldLogin = await t.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: { emailOrPhone: email, pin: '1111' }
      });
      assert.equal(oldLogin.status, 401);
      const newLogin = await t.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: { emailOrPhone: email, pin: '998877' }
      });
      assert.equal(newLogin.status, 200);
    });

    it('rejects a wrong OTP with 401 INVALID_OTP', async () => {
      const email = 'pin.reset2@safesphere.test';
      const phone = '+918811223355';
      const reg = await t.request('/api/v1/auth/register', {
        method: 'POST',
        body: { name: 'Pin Reset Two', email, phone, password: 'Str0ngPass!23' }
      });
      assert.equal(reg.status, 201);

      // An OTP must exist first — otherwise verifyOtp 400s on the missing record
      const send = await t.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone, purpose: 'login' }
      });
      assert.equal(send.status, 200);

      const reset = await t.request('/api/v1/auth/pin/reset', {
        method: 'POST',
        body: { phone, otp: '000000', newPin: '998877' }
      });
      assert.equal(reset.status, 401);
      assert.equal(reset.body.error.code, 'INVALID_OTP');
    });

    it('rejects invalid new PIN format with 400', async () => {
      const email = 'pin.reset3@safesphere.test';
      const phone = '+918811223366';
      await t.request('/api/v1/auth/register', {
        method: 'POST',
        body: { name: 'Pin Reset Three', email, phone, password: 'Str0ngPass!23' }
      });
      const send = await t.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone, purpose: 'login' }
      });
      assert.equal(send.status, 200);
      const devOtp = send.body.devOtp;
      const reset = await t.request('/api/v1/auth/pin/reset', {
        method: 'POST',
        body: { phone, otp: devOtp, newPin: '12' }
      });
      assert.equal(reset.status, 400);
      assert.ok(reset.body.error.details.some(d => d.field === 'newPin'));
    });
  });

  describe('6. Env fail-closed for unknown NODE_ENV values', () => {    const backendDir = path.resolve(__dirname, '..');

    function bootWith(env) {
      let result;
      try {
        execFileSync(process.execPath, ['-e', 'require("./src/config")'], {
          cwd: backendDir,
          env: { ...process.env, ...env },
          stdio: ['ignore', 'pipe', 'pipe'],
          timeout: 10000
        });
        result = { code: 0 };
      } catch (e) {
        result = { code: e.status, stderr: e.stderr ? String(e.stderr) : '' };
      }
      return result;
    }

    it('unknown NODE_ENV (staging) without JWT secrets refuses to boot', () => {
      const r = bootWith({ NODE_ENV: 'staging' });
      assert.notEqual(r.code, 0, 'unknown env must be treated as production: missing secrets must fail boot');
      assert.match(r.stderr, /INSECURE_JWT_CONFIG|JWT/);
    });

    it('known development env still boots without secrets (dev convenience)', () => {
      const r = bootWith({ NODE_ENV: 'development' });
      assert.equal(r.code, 0);
    });

    it('production env without JWT secrets refuses to boot (unchanged behavior)', () => {
      const r = bootWith({ NODE_ENV: 'production' });
      assert.notEqual(r.code, 0);
    });
  });
});
