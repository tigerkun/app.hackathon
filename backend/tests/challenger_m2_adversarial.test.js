/**
 * SafeSphere Milestone 2: Adversarial Empirical Challenge & Stress Test Suite
 * Author: Challenger 1 (teamwork_preview_challenger_m2_1_gen2)
 * Target: Backend Layered Architecture & Auth Service (/api/v1/auth/*)
 *
 * This test suite executes rigorous adversarial attack scenarios, boundary stress testing,
 * state-machine concurrency/replay verification, and failure mode mining across:
 * 1. Registration validation (missing fields, boundary lengths, duplicate collisions, formatting)
 * 2. Login credential validation (tampered, deactivated, case-insensitivity, whitespace, PIN)
 * 3. Cryptographic OTP flow (60s cooldown, 3-attempt lockout, anti-replay, expired, malformed)
 * 4. Dual-token JWT lifecycle (refresh, forgery, secret cross-contamination, session invalidation)
 * 5. Protected route /api/v1/auth/me (header variations, expired tokens, revoked sessions)
 * 6. Multi-modal biometrics endpoints (unauthenticated rejection, valid registration, login)
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const config = require('../src/config');
const { signAccessToken } = require('../src/services/tokenService');

describe('SafeSphere Milestone 2: Adversarial Stress & Edge Case Verification', () => {
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
  // 1. Registration Validation, Boundary Stress & Duplicate Collisions
  // ===========================================================================
  describe('1. Adversarial Registration Validation & Collision Stress', () => {
    it('rejects completely empty registration body with 400 and comprehensive error details', async () => {
      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {}
      });

      assert.equal(res.status, 400, `Expected 400, got ${res.status}`);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
      assert.ok(Array.isArray(res.body.error.details));
      const fields = res.body.error.details.map((d) => d.field);
      assert.ok(fields.includes('name'), 'Should flag missing name');
      assert.ok(fields.includes('email'), 'Should flag missing email');
      assert.ok(fields.includes('phone'), 'Should flag missing phone');
      assert.ok(fields.includes('password'), 'Should flag missing password');
    });

    it('rejects registration with whitespace-only fields with 400', async () => {
      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: '   ',
          email: '   ',
          phone: '   ',
          password: '        '
        }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('validates name length boundaries: rejects 1 char, rejects 101 chars, accepts 2 chars, accepts 100 chars', async () => {
      // 1 char name -> rejects
      const res1 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'A',
          email: 'boundary1@safesphere.org',
          phone: '+91 9911000001',
          password: 'ValidPassword123!'
        }
      });
      assert.equal(res1.status, 400);
      assert.equal(res1.body.error.details[0].field, 'name');

      // 101 chars name -> rejects
      const res101 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'A'.repeat(101),
          email: 'boundary101@safesphere.org',
          phone: '+91 9911000002',
          password: 'ValidPassword123!'
        }
      });
      assert.equal(res101.status, 400);
      assert.equal(res101.body.error.details[0].field, 'name');

      // 2 chars name -> accepts
      const res2 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Al',
          email: 'boundary2@safesphere.org',
          phone: '+91 9911000003',
          password: 'ValidPassword123!'
        }
      });
      assert.equal(res2.status, 201);
      assert.equal(res2.body.data.user.name, 'Al');

      // 100 chars name -> accepts
      const res100 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'B'.repeat(100),
          email: 'boundary100@safesphere.org',
          phone: '+91 9911000004',
          password: 'ValidPassword123!'
        }
      });
      assert.equal(res100.status, 201);
      assert.equal(res100.body.data.user.name, 'B'.repeat(100));
    });

    it('rejects invalid email formats (missing @, missing domain, spaces, empty string)', async () => {
      const badEmails = [
        'plainaddress',
        '@missinguser.com',
        'missingdomain@.com',
        'spaces in@domain.com',
        'missing-domain@',
        'not_an_email'
      ];

      for (const email of badEmails) {
        const res = await serverHarness.request('/api/v1/auth/register', {
          method: 'POST',
          body: {
            name: 'Test User',
            email,
            phone: '+91 9911223344',
            password: 'ValidPassword123!'
          }
        });
        assert.equal(res.status, 400, `Expected 400 for bad email "${email}", got ${res.status}`);
        assert.equal(res.body.error.code, 'VALIDATION_ERROR');
      }
    });

    it('enforces email case-insensitive uniqueness (prevents registration collision bypass via uppercase)', async () => {
      // Demo user exists with lowercase email: demo@safesphere.org
      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Imposter Demo',
          email: 'DEMO@SAFESPHERE.ORG', // Uppercase variant
          phone: '+91 9988776655',
          password: 'Password123!'
        }
      });

      assert.equal(res.status, 409, `Expected 409 Conflict for uppercase email collision, got ${res.status}`);
      assert.equal(res.body.error.code, 'USER_ALREADY_EXISTS');
    });

    it('rejects duplicate phone number even with different email address', async () => {
      // Demo user has phone: +91 9876543210
      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Duplicate Phone User',
          email: 'newemail@safesphere.org',
          phone: '+91 9876543210',
          password: 'Password123!'
        }
      });

      assert.equal(res.status, 409, `Expected 409 Conflict for duplicate phone, got ${res.status}`);
      assert.equal(res.body.error.code, 'USER_ALREADY_EXISTS');
    });

    it('enforces password length boundary (7 characters rejected, 8 characters accepted)', async () => {
      const res7 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Seven Char',
          email: 'seven@safesphere.org',
          phone: '+91 9900112233',
          password: '1234567' // 7 chars
        }
      });
      assert.equal(res7.status, 400);

      const res8 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Eight Char',
          email: 'eight@safesphere.org',
          phone: '+91 9900112233',
          password: '12345678' // 8 chars
        }
      });
      assert.equal(res8.status, 201);
    });

    it('validates PIN format: rejects 3 digits, rejects 7 digits, rejects letters, accepts 4-6 digits', async () => {
      const invalidPins = ['123', '1234567', 'abcd', '12a4'];
      for (const pin of invalidPins) {
        const res = await serverHarness.request('/api/v1/auth/register', {
          method: 'POST',
          body: {
            name: 'Pin Test',
            email: `pin_${pin}@safesphere.org`,
            phone: '+91 9900112244',
            password: 'ValidPassword123!',
            pin
          }
        });
        assert.equal(res.status, 400, `Expected 400 for invalid pin "${pin}", got ${res.status}`);
      }

      // Valid 4-digit PIN
      const res4 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Pin 4',
          email: 'pin4@safesphere.org',
          phone: '+91 9900112245',
          password: 'ValidPassword123!',
          pin: '5678'
        }
      });
      assert.equal(res4.status, 201);
      assert.equal(res4.body.data.user.hasPin, true);

      // Valid 6-digit PIN
      const res6 = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Pin 6',
          email: 'pin6@safesphere.org',
          phone: '+91 9900112246',
          password: 'ValidPassword123!',
          pin: '123456'
        }
      });
      assert.equal(res6.status, 201);
      assert.equal(res6.body.data.user.hasPin, true);
    });

    it('verifies that sensitive fields (passwordHash, salt) are never leaked in response', async () => {
      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Security Audit User',
          email: 'audit@safesphere.org',
          phone: '+91 9900112247',
          password: 'SuperSecretPassword123!'
        }
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.user.passwordHash, undefined);
      assert.equal(res.body.data.user.passwordHash, undefined);
      assert.equal(res.body.user.salt, undefined);
      assert.equal(res.body.data.user.salt, undefined);
    });
  });

  // ===========================================================================
  // 2. Login Credential Validation & Stress
  // ===========================================================================
  describe('2. Adversarial Login Credential Validation & Stress', () => {
    it('authenticates with case-insensitive email (UPPERCASE login)', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'DEMO@SAFESPHERE.ORG',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.user.email, 'demo@safesphere.org');
    });

    it('authenticates with trimmed whitespace around email or phone', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: '   demo@safesphere.org   ',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
    });

    it('rejects wrong password with generic 401 INVALID_CREDENTIALS error envelope', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'IncorrectPassword'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
    });

    it('rejects non-existent account with same 401 INVALID_CREDENTIALS error envelope (timing-safe parity)', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'nonexistent_ghost_user@safesphere.org',
          password: 'SomePassword123!'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
    });

    it('rejects deactivated user account with 403 ACCOUNT_DEACTIVATED', async () => {
      // Deactivate demo user
      const user = db.findUserByEmail('demo@safesphere.org');
      db.updateUser(user.id, { isActive: false });

      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 403);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'ACCOUNT_DEACTIVATED');
    });

    it('handles SQLi and NoSQL injection payloads gracefully without crashing (500)', async () => {
      const maliciousPayloads = [
        { emailOrPhone: "' OR 1=1 --", password: "' OR 1=1 --" },
        { emailOrPhone: 'admin@safesphere.org\' UNION SELECT * FROM users --', password: 'xyz' },
        { emailOrPhone: '{"$gt": ""}', password: 'xyz' }
      ];

      for (const payload of maliciousPayloads) {
        const res = await serverHarness.request('/api/v1/auth/login', {
          method: 'POST',
          body: payload
        });
        assert.notEqual(res.status, 500, `Injection payload caused 500 server crash: ${JSON.stringify(payload)}`);
        assert.equal(res.status, 401);
      }
    });

    it('handles extremely large password payload (DoS stress test) without hanging', async () => {
      const hugePassword = 'A'.repeat(50000);
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: hugePassword
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });
  });

  // ===========================================================================
  // 3. OTP Flow: 60s Cooldown, 3-Attempt Lockout, Expiry & Anti-Replay
  // ===========================================================================
  describe('3. Adversarial Cryptographic OTP Flow & Lockout Stress', () => {
    const testPhone = '+91 9876543210';

    it('enforces 60-second cooldown rate limit even if phone number has trailing whitespace', async () => {
      // 1. Initial send
      const res1 = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      assert.equal(res1.status, 200);

      // 2. Immediate second request with trailing space
      const res2 = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: `${testPhone}   ` }
      });

      assert.equal(res2.status, 429);
      assert.equal(res2.body.error.code, 'OTP_COOLDOWN_ACTIVE');
      assert.ok(res2.headers.get('retry-after'));
    });

    it('enforces strict 3-attempt lockout: wipes OTP record and blocks subsequent verification', async () => {
      // 1. Send OTP
      const sendRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      assert.equal(sendRes.status, 200);
      const trueOtp = sendRes.body.data.devOtp;

      // 2. Attempt 1 with invalid code -> 401 (remaining: 2)
      const a1 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '000001' }
      });
      assert.equal(a1.status, 401);
      assert.equal(a1.body.error.code, 'INVALID_OTP');
      assert.match(a1.body.error.message, /2 attempts remaining/);

      // 3. Attempt 2 with invalid code -> 401 (remaining: 1)
      const a2 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '000002' }
      });
      assert.equal(a2.status, 401);
      assert.match(a2.body.error.message, /1 attempts remaining/);

      // 4. Attempt 3 with invalid code -> 429 Lockout & OTP record purged
      const a3 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '000003' }
      });
      assert.equal(a3.status, 429);
      assert.equal(a3.body.error.code, 'OTP_MAX_ATTEMPTS_EXCEEDED');

      // 5. Attempt 4: Even presenting the TRUE original OTP after lockout MUST FAIL
      const a4 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: trueOtp }
      });
      assert.equal(a4.status, 400, 'Original OTP must be wiped after lockout and rejected');
      assert.equal(a4.body.error.code, 'OTP_EXPIRED');
    });

    it('enforces single-use consumption: replaying a verified OTP immediately fails with 400 OTP_EXPIRED', async () => {
      // Send OTP
      const sendRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      const code = sendRes.body.data.devOtp;

      // First verification succeeds
      const v1 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: code }
      });
      assert.equal(v1.status, 200);
      assert.equal(v1.body.data.verified, true);

      // Replay attempt with same code must be rejected
      const v2 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: code }
      });
      assert.equal(v2.status, 400, 'Replayed OTP must be rejected');
      assert.equal(v2.body.error.code, 'OTP_EXPIRED');
    });

    it('rejects expired OTP when TTL has lapsed', async () => {
      // Send OTP
      const sendRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      const code = sendRes.body.data.devOtp;

      // Artificially expire the OTP in store
      const record = db.getOtp(testPhone);
      record.expiresAt = Date.now() - 1000; // Expired 1 second ago
      db.saveOtp(testPhone, record);

      // Verification fails
      const res = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: code }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'OTP_EXPIRED');
    });

    it('rejects malformed OTP input formats (letters, 5 digits, 7 digits, symbols)', async () => {
      const badOtps = ['12345', '1234567', 'abcdef', '12a456', '!!!!!!'];
      for (const otp of badOtps) {
        const res = await serverHarness.request('/api/v1/auth/otp/verify', {
          method: 'POST',
          body: { phone: testPhone, otp }
        });
        assert.equal(res.status, 400, `Expected 400 for bad OTP format "${otp}"`);
        assert.equal(res.body.error.code, 'VALIDATION_ERROR');
      }
    });

    it('handles OTP verification for unregistered phone returning phoneVerifiedToken receipt for registration', async () => {
      const newPhone = '+91 9112233445';
      const sendRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: newPhone }
      });
      assert.equal(sendRes.status, 200);

      const code = sendRes.body.data.devOtp;
      const verifyRes = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: newPhone, otp: code }
      });

      assert.equal(verifyRes.status, 200);
      assert.equal(verifyRes.body.data.verified, true);
      assert.ok(verifyRes.body.data.phoneVerifiedToken, 'Should return phoneVerifiedToken for new user');
    });
  });

  // ===========================================================================
  // 4. Dual-Token JWT Lifecycle & Refresh Security
  // ===========================================================================
  describe('4. Adversarial Token Refresh & Session Lifecycle Stress', () => {
    it('rejects forged refresh token signed with wrong secret key', async () => {
      const fakeToken = jwt.sign(
        { sub: 'usr_fake', sessionId: 'ses_fake' },
        'attacker_malicious_private_key_1234',
        { expiresIn: 3600 }
      );

      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: fakeToken }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_REFRESH_TOKEN');
    });

    it('rejects access token passed as refresh token (secret cross-contamination defense)', async () => {
      // Obtain valid access token
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const accessToken = loginRes.body.data.accessToken;

      // Attempt to refresh using the ACCESS token
      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: accessToken }
      });

      assert.equal(res.status, 401, 'Access token must not be accepted by refresh endpoint');
      assert.equal(res.body.error.code, 'INVALID_REFRESH_TOKEN');
    });

    it('rejects expired refresh token with 401 INVALID_REFRESH_TOKEN', async () => {
      const expiredToken = jwt.sign(
        { sub: 'usr_demo', sessionId: 'ses_expired' },
        config.refreshSecret,
        { expiresIn: -10 } // Expired 10s ago
      );

      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: expiredToken }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_REFRESH_TOKEN');
    });

    it('rejects refresh when session is revoked via logout or administrative termination', async () => {
      // 1. Login
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const { accessToken, refreshToken } = loginRes.body.data;

      // 2. Perform logout
      const logoutRes = await serverHarness.request('/api/v1/auth/logout', {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}` },
        body: { refreshToken }
      });
      assert.equal(logoutRes.status, 200);

      // 3. Refresh with revoked token
      const refreshRes = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken }
      });

      assert.equal(refreshRes.status, 401);
      assert.equal(refreshRes.body.error.code, 'INVALID_SESSION');
    });

    it('rejects refresh if the user account has been deactivated after token was issued', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const { refreshToken } = loginRes.body.data;

      // Deactivate user
      const user = db.findUserByEmail('demo@safesphere.org');
      db.updateUser(user.id, { isActive: false });

      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'USER_INACTIVE');
    });
  });

  // ===========================================================================
  // 5. Protected Route /api/v1/auth/me & Security Middleware
  // ===========================================================================
  describe('5. Adversarial Protected Route (/api/v1/auth/me) & Middleware Stress', () => {
    it('rejects malformed Authorization headers (empty Bearer, wrong scheme, garbage)', async () => {
      const malformedHeaders = [
        'Bearer',
        'Bearer ',
        'Bearer    ',
        'Token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz',
        'Basic dXNlcjpwYXNz',
        'Digest username="test"',
        'invalid_scheme_without_space',
        'Bearer null',
        'Bearer undefined'
      ];

      for (const header of malformedHeaders) {
        const res = await serverHarness.request('/api/v1/auth/me', {
          headers: { Authorization: header }
        });
        assert.equal(res.status, 401, `Expected 401 for header "${header}", got ${res.status}`);
        assert.equal(res.body.success, false);
      }
    });

    it('rejects expired access token with 401 and INVALID_TOKEN code', async () => {
      const expiredAccessToken = jwt.sign(
        { sub: 'usr_demo_1001', email: 'demo@safesphere.org', sessionId: 'ses_123' },
        config.jwtSecret,
        { expiresIn: -10 }
      );

      const res = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${expiredAccessToken}` }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_TOKEN');
      assert.equal(res.body.error.message, 'Token expired');
    });

    it('rejects refresh token sent to protected route (wrong signing secret defense)', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const refreshToken = loginRes.body.data.refreshToken;

      const res = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${refreshToken}` }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'INVALID_TOKEN');
    });

    it('rejects access token when session is invalidated (instant session termination)', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const accessToken = loginRes.body.data.accessToken;

      // Extract payload to get sessionId
      const decoded = jwt.decode(accessToken);
      assert.ok(decoded.sessionId);

      // Invalidate session in DB
      db.invalidateSession(decoded.sessionId);

      // Request to /me must now be rejected with 401 SESSION_REVOKED
      const res = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${accessToken}` }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'SESSION_REVOKED');
    });

    it('rejects access token if user has been deactivated in database', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const accessToken = loginRes.body.data.accessToken;

      // Deactivate user
      const user = db.findUserByEmail('demo@safesphere.org');
      db.updateUser(user.id, { isActive: false });

      const res = await serverHarness.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${accessToken}` }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error.code, 'USER_INACTIVE');
    });
  });

  // ===========================================================================
  // 6. Multi-Modal Biometric Flow Verification
  // ===========================================================================
  describe('6. Multi-Modal Biometric Flow & Edge Cases', () => {
    it('rejects biometric registration without authenticated Bearer token with 401', async () => {
      const res = await serverHarness.request('/api/v1/auth/biometrics/register', {
        method: 'POST',
        body: { biometricToken: 'bio_device_signature_123' }
      });

      assert.equal(res.status, 401);
    });

    it('rejects biometric registration without biometricToken with 400', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const token = loginRes.body.data.accessToken;

      const res = await serverHarness.request('/api/v1/auth/biometrics/register', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: {}
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('completes end-to-end biometric registration and subsequent biometric login', async () => {
      // 1. Login with password
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const token = loginRes.body.data.accessToken;

      // 2. Register biometric token
      const bioKey = 'bio_fingerprint_secure_token_999888';
      const regRes = await serverHarness.request('/api/v1/auth/biometrics/register', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: { biometricToken: bioKey }
      });
      assert.equal(regRes.status, 200);
      assert.equal(regRes.body.data.biometricsEnabled, true);

      // 3. Login using biometric token
      const bioLoginRes = await serverHarness.request('/api/v1/auth/biometrics/login', {
        method: 'POST',
        body: { biometricToken: bioKey }
      });
      assert.equal(bioLoginRes.status, 200);
      assert.ok(bioLoginRes.body.data.accessToken);
      assert.equal(bioLoginRes.body.data.user.email, 'demo@safesphere.org');

      // 4. Attempt login with an UNREGISTERED biometric token -> 401
      const badBioRes = await serverHarness.request('/api/v1/auth/biometrics/login', {
        method: 'POST',
        body: { biometricToken: 'unregistered_bio_token_xyz' }
      });
      assert.equal(badBioRes.status, 401);
      assert.equal(badBioRes.body.error.code, 'INVALID_BIOMETRICS');
    });
  });
});
