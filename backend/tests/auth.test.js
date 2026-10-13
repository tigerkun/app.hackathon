/**
 * SafeSphere Auth Service Automated Test Suite
 * Native Node.js test runner using node:test and node:assert/strict.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');

describe('SafeSphere Authentication API & Service Tests', () => {
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
  // 1. User Registration
  // ===========================================================================
  describe('User Registration (POST /api/v1/auth/register)', () => {
    it('successfully registers a new user with valid details returning 201 Created', async () => {
      const payload = {
        name: 'Aarav Sharma',
        email: 'aarav@safesphere.org',
        phone: '+91 9911223344',
        password: 'SecurePassword2026!',
        pin: '4321',
        emergencyContact: {
          name: 'Priya Sharma',
          phone: '+91 9911223355',
          relationship: 'Sister'
        }
      };

      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 201, `Expected 201 Created, got ${res.status}`);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.accessToken, 'Access token should be issued');
      assert.ok(res.body.data.refreshToken, 'Refresh token should be issued');
      assert.equal(res.body.data.user.email, 'aarav@safesphere.org');
      assert.equal(res.body.data.user.hasPin, true);
      assert.equal(res.body.data.user.emergencyContacts.length, 1);
      assert.equal(res.body.data.user.passwordHash, undefined, 'passwordHash must never be exposed');
    });

    it('rejects registration with duplicate email with 409 Conflict', async () => {
      const payload = {
        name: 'Another User',
        email: 'demo@safesphere.org', // Already in seed data
        phone: '+91 9999000011',
        password: 'Password123!'
      };

      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 409, `Expected 409 Conflict, got ${res.status}`);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'USER_ALREADY_EXISTS');
    });

    it('rejects registration with invalid email format with 400 Bad Request', async () => {
      const payload = {
        name: 'Bad Email User',
        email: 'invalid-email-address',
        phone: '+91 9999000012',
        password: 'Password123!'
      };

      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('rejects registration with password shorter than 8 characters with 400 Bad Request', async () => {
      const payload = {
        name: 'Short Pass User',
        email: 'short@safesphere.org',
        phone: '+91 9999000013',
        password: 'short'
      };

      const res = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });
  });

  // ===========================================================================
  // 2. User Login
  // ===========================================================================
  describe('User Login (POST /api/v1/auth/login)', () => {
    it('authenticates demo user with valid credentials returning 200 OK and tokens', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 200, `Expected 200 OK, got ${res.status}`);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.accessToken);
      assert.ok(res.body.data.refreshToken);
      assert.equal(res.body.data.user.email, 'demo@safesphere.org');
      assert.equal(res.body.data.user.name, 'Jane SafeSphere');
    });

    it('authenticates user using phone number instead of email', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: '+91 9876543210',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.user.phone, '+91 9876543210');
    });

    it('rejects login with invalid password returning 401 Unauthorized', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'WrongPassword2026'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
    });

    it('rejects login with non-existent account returning 401 Unauthorized', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'nonexistent@safesphere.org',
          password: 'SomePassword123'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });

    it('rejects login with missing password returning 400 Bad Request', async () => {
      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org'
        }
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });
  });

  // ===========================================================================
  // 3. Multi-Modal PIN Login
  // ===========================================================================
  describe('Quick Emergency PIN Login (POST /api/v1/auth/login-pin)', () => {
    it('authenticates demo user with configured PIN returning 200 OK and tokens', async () => {
      const res = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          pin: '1234'
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.accessToken);
      assert.equal(res.body.data.user.email, 'demo@safesphere.org');
    });

    it('rejects incorrect PIN with 401 Unauthorized', async () => {
      const res = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          pin: '9999'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_PIN');
    });
  });

  // ===========================================================================
  // 4. Cryptographic SMS OTP Flow
  // ===========================================================================
  describe('Cryptographic SMS OTP Flow (/api/v1/auth/otp/*)', () => {
    const testPhone = '+91 9876543210';

    it('sends 6-digit OTP and includes devOtp in test/dev environment', async () => {
      const res = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.devOtp, 'devOtp should be provided in test environment');
      assert.match(res.body.data.devOtp, /^\d{6}$/, 'OTP must be exactly 6 numeric digits');
    });

    it('enforces 60-second cooldown rate limit returning 429 Too Many Requests', async () => {
      // First request succeeds
      const firstRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      assert.equal(firstRes.status, 200);

      // Immediate second request must trigger cooldown
      const secondRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });

      assert.equal(secondRes.status, 429, `Expected 429 Too Many Requests, got ${secondRes.status}`);
      assert.equal(secondRes.body.success, false);
      assert.equal(secondRes.body.error.code, 'OTP_COOLDOWN_ACTIVE');
      assert.ok(secondRes.headers.get('retry-after'), 'Retry-After header must be present');
    });

    it('verifies valid OTP for registered user and issues dual JWT session tokens', async () => {
      // Send OTP
      const sendRes = await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });
      const code = sendRes.body.data.devOtp;

      // Verify OTP
      const verifyRes = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: code }
      });

      assert.equal(verifyRes.status, 200);
      assert.equal(verifyRes.body.success, true);
      assert.equal(verifyRes.body.data.verified, true);
      assert.ok(verifyRes.body.data.accessToken);
      assert.equal(verifyRes.body.data.user.phone, testPhone);
    });

    it('rejects incorrect OTP code returning 401 Unauthorized', async () => {
      // Send OTP
      await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });

      // Verify with wrong code
      const verifyRes = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '000000' }
      });

      assert.equal(verifyRes.status, 401);
      assert.equal(verifyRes.body.success, false);
      assert.equal(verifyRes.body.error.code, 'INVALID_OTP');
    });

    it('locks out and wipes OTP after 3 failed attempts returning 429', async () => {
      // Send OTP
      await serverHarness.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: testPhone }
      });

      // Attempt 1 (wrong) -> 401
      const res1 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '111111' }
      });
      assert.equal(res1.status, 401);

      // Attempt 2 (wrong) -> 401
      const res2 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '222222' }
      });
      assert.equal(res2.status, 401);

      // Attempt 3 (wrong) -> 429 Lockout
      const res3 = await serverHarness.request('/api/v1/auth/otp/verify', {
        method: 'POST',
        body: { phone: testPhone, otp: '333333' }
      });
      assert.equal(res3.status, 429);
      assert.equal(res3.body.error.code, 'OTP_MAX_ATTEMPTS_EXCEEDED');
    });
  });

  // ===========================================================================
  // 5. Dual-Token JWT Lifecycle & Refresh
  // ===========================================================================
  describe('Token Refresh (POST /api/v1/auth/refresh)', () => {
    it('successfully exchanges valid refresh token for a fresh access token', async () => {
      // Login to obtain tokens
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const refreshToken = loginRes.body.data.refreshToken;

      // Call refresh
      const refreshRes = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken }
      });

      assert.equal(refreshRes.status, 200);
      assert.equal(refreshRes.body.success, true);
      assert.ok(refreshRes.body.data.accessToken, 'New access token must be generated');
      assert.equal(refreshRes.body.data.tokenType, 'Bearer');
    });

    it('rejects tampered or forged refresh token returning 401 Unauthorized', async () => {
      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.tampered.signature' }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });

    it('rejects missing refresh token returning 400 Bad Request', async () => {
      const res = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: {}
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
    });
  });

  // ===========================================================================
  // 6. Protected User Profile Route
  // ===========================================================================
  describe('Protected Profile Route (GET /api/v1/auth/me)', () => {
    it('returns user profile and emergency contacts when presented with valid Bearer token', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const token = loginRes.body.data.accessToken;

      const profileRes = await serverHarness.request('/api/v1/auth/me', {
        headers: {
          Authorization: `Bearer ${token}`
        }
      });

      assert.equal(profileRes.status, 200);
      assert.equal(profileRes.body.success, true);
      assert.equal(profileRes.body.data.email, 'demo@safesphere.org');
      assert.ok(Array.isArray(profileRes.body.data.emergencyContacts));
      assert.equal(profileRes.body.data.emergencyContacts.length, 2);
    });

    it('returns 401 Unauthorized when Authorization header is absent', async () => {
      const res = await serverHarness.request('/api/v1/auth/me');

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'UNAUTHORIZED');
    });

    it('returns 401 Unauthorized when Bearer token is invalid or corrupted', async () => {
      const res = await serverHarness.request('/api/v1/auth/me', {
        headers: {
          Authorization: 'Bearer invalid.corrupted.token'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });
  });

  // ===========================================================================
  // 7. Session Logout & Revocation
  // ===========================================================================
  describe('Session Logout & Revocation (POST /api/v1/auth/logout)', () => {
    it('invalidates current session on logout and rejects subsequent token refresh', async () => {
      const loginRes = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });
      const { accessToken, refreshToken } = loginRes.body.data;

      // Logout
      const logoutRes = await serverHarness.request('/api/v1/auth/logout', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`
        },
        body: { refreshToken }
      });

      assert.equal(logoutRes.status, 200);
      assert.equal(logoutRes.body.success, true);

      // Attempting to refresh using revoked session must be rejected with 401
      const refreshAfterLogout = await serverHarness.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: { refreshToken }
      });

      assert.equal(refreshAfterLogout.status, 401, 'Revoked session refresh must return 401');
      assert.equal(refreshAfterLogout.body.error.code, 'INVALID_SESSION');
    });
  });
});
