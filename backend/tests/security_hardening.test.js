/**
 * SafeSphere Security Hardening Test Suite (Milestone M1)
 *
 * Covers:
 * 1. Demo Account Gating in Dev/Test vs Non-Demo/Production
 * 2. Login Rejection for Demo User in Non-Demo Mode (Password & PIN)
 * 3. JWT Secret Hygiene Validation (Missing, Blank, Denylisted, Identical, Short Secrets)
 * 4. Bcrypt PIN Hashing on Registration & Verification on Login
 * 5. Sanitization of User Entities (no leaked pin/pinHash/passwordHash)
 * 6. Backward Compatibility Fallback for Unhashed Legacy PINs
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const config = require('../src/config');
const { validateJwtSecretHygiene, INSECURE_SECRET_DENYLIST } = config;
const { toSafeUser, createUser } = require('../src/models/userModel');

describe('SafeSphere Backend Security Hardening Tests (Milestone M1)', () => {
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
  // 1. Demo Account Seed Gating & Login Rejection in Non-Demo Mode
  // ===========================================================================
  describe('Demo Account Seed Gating & Production Isolation', () => {
    it('seeds demo user by default in test/development mode', () => {
      db.reset();
      const demoUser = db.findUserByEmail('demo@safesphere.org');
      assert.ok(demoUser, 'Demo user should be seeded in test environment');
      assert.equal(demoUser.email, 'demo@safesphere.org');
      assert.ok(db.reports.size >= 3, 'Incident reports should be seeded');
      assert.ok(db.markers.size >= 3, 'Safety markers should be seeded');
    });

    it('does NOT seed demo user when demoMode is explicitly false', () => {
      db.reset({ demoMode: false });
      const demoUser = db.findUserByEmail('demo@safesphere.org');
      assert.equal(demoUser, null, 'Demo user must NOT exist when demoMode is false');

      const allUsers = db.getAllUsers();
      const foundDemo = allUsers.some((u) => u.email === 'demo@safesphere.org' || u.id === 'user_safesphere_demo_01');
      assert.equal(foundDemo, false, 'No demo user should be present in users collection');

      // Crucial: Safety markers and incident reports must remain seeded for platform operation
      assert.ok(db.reports.size >= 3, 'Reports must remain seeded even when demoMode is false');
      assert.ok(db.markers.size >= 3, 'Safety markers must remain seeded even when demoMode is false');
    });

    it('rejects password login for demo user when demo mode is disabled', async () => {
      db.reset({ demoMode: false });

      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 401, `Expected 401 Unauthorized, got ${res.status}`);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
    });

    it('rejects PIN login for demo user when demo mode is disabled', async () => {
      db.reset({ demoMode: false });

      const res = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          pin: '1234'
        }
      });

      assert.equal(res.status, 401, `Expected 401 Unauthorized, got ${res.status}`);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_PIN_CREDENTIALS');
    });

    it('restores demo user and permits login when demoMode is enabled', async () => {
      db.reset({ demoMode: true });

      const res = await serverHarness.request('/api/v1/auth/login', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          password: 'SafeSphere@2026'
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.user.email, 'demo@safesphere.org');
    });
  });

  // ===========================================================================
  // 2. JWT Secret Hygiene Validation
  // ===========================================================================
  describe('JWT Secret Hygiene Validation', () => {
    const valid32ByteSecret1 = 'a_very_secure_production_jwt_secret_key_with_over_32_chars!';
    const valid32ByteSecret2 = 'another_distinct_production_refresh_secret_key_32_chars!!';

    it('passes validation in production when both secrets are strong, distinct, and >= 32 characters', () => {
      const result = validateJwtSecretHygiene({
        jwtSecret: valid32ByteSecret1,
        refreshSecret: valid32ByteSecret2,
        nodeEnv: 'production'
      });

      assert.equal(result.valid, true);
      assert.deepEqual(result.warnings, []);
    });

    it('throws INSECURE_JWT_CONFIG if jwtSecret is missing in production', () => {
      assert.throws(
        () => {
          validateJwtSecretHygiene({
            jwtSecret: '',
            refreshSecret: valid32ByteSecret2,
            nodeEnv: 'production'
          });
        },
        (err) => {
          assert.equal(err.code, 'INSECURE_JWT_CONFIG');
          assert.ok(err.message.includes('JWT_SECRET must be explicitly set'));
          return true;
        }
      );
    });

    it('throws INSECURE_JWT_CONFIG if refreshSecret is missing or whitespace in production', () => {
      assert.throws(
        () => {
          validateJwtSecretHygiene({
            jwtSecret: valid32ByteSecret1,
            refreshSecret: '   ',
            nodeEnv: 'production'
          });
        },
        (err) => {
          assert.equal(err.code, 'INSECURE_JWT_CONFIG');
          assert.ok(err.message.includes('JWT_REFRESH_SECRET must be explicitly set'));
          return true;
        }
      );
    });

    it('throws INSECURE_JWT_CONFIG if secrets match insecure denylist in production', () => {
      for (const denylisted of INSECURE_SECRET_DENYLIST) {
        assert.throws(
          () => {
            validateJwtSecretHygiene({
              jwtSecret: denylisted,
              refreshSecret: valid32ByteSecret2,
              nodeEnv: 'production'
            });
          },
          (err) => {
            assert.equal(err.code, 'INSECURE_JWT_CONFIG');
            assert.ok(err.message.includes('insecure default secret'));
            return true;
          },
          `Should have thrown for denylisted secret: ${denylisted}`
        );
      }
    });

    it('enforces case-insensitive denylist matching', () => {
      assert.throws(
        () => {
          validateJwtSecretHygiene({
            jwtSecret: 'SAFESPHERE_DEV_JWT_SECRET_KEY_2026_SUPER_SECURE',
            refreshSecret: valid32ByteSecret2,
            nodeEnv: 'production'
          });
        },
        (err) => {
          assert.equal(err.code, 'INSECURE_JWT_CONFIG');
          return true;
        }
      );
    });

    it('throws INSECURE_JWT_CONFIG if jwtSecret and refreshSecret are identical', () => {
      assert.throws(
        () => {
          validateJwtSecretHygiene({
            jwtSecret: valid32ByteSecret1,
            refreshSecret: valid32ByteSecret1,
            nodeEnv: 'production'
          });
        },
        (err) => {
          assert.equal(err.code, 'INSECURE_JWT_CONFIG');
          assert.ok(err.message.includes('must not be identical'));
          return true;
        }
      );
    });

    it('throws INSECURE_JWT_CONFIG if secrets are shorter than 32 characters in production', () => {
      assert.throws(
        () => {
          validateJwtSecretHygiene({
            jwtSecret: 'short_secret_under_32_chars!',
            refreshSecret: valid32ByteSecret2,
            nodeEnv: 'production'
          });
        },
        (err) => {
          assert.equal(err.code, 'INSECURE_JWT_CONFIG');
          assert.ok(err.message.includes('at least 32 characters'));
          return true;
        }
      );
    });

    it('permits default secrets without throwing in development or test modes', () => {
      const devResult = validateJwtSecretHygiene({
        jwtSecret: 'safesphere_dev_jwt_secret_key_2026_super_secure',
        refreshSecret: 'safesphere_dev_jwt_refresh_secret_key_2026_super_secure',
        nodeEnv: 'development'
      });
      assert.equal(devResult.valid, true);

      const testResult = validateJwtSecretHygiene({
        jwtSecret: 'short',
        refreshSecret: 'short',
        nodeEnv: 'test'
      });
      assert.equal(testResult.valid, true);
    });
  });

  // ===========================================================================
  // 3. Bcrypt PIN Hashing on Registration & Verification on Login
  // ===========================================================================
  describe('Bcrypt PIN Hashing & Authentication Verification', () => {
    it('persists bcrypt hash for 4-digit PIN on registration and authenticates via login-pin', async () => {
      const payload = {
        name: 'Rohan Verma',
        email: 'rohan@safesphere.org',
        phone: '+91 9811223344',
        password: 'RohanPassword2026!',
        pin: '2468'
      };

      const regRes = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(regRes.status, 201);
      assert.equal(regRes.body.data.user.hasPin, true);
      assert.equal(regRes.body.data.user.pin, undefined, 'Raw pin must never be in registration response');
      assert.equal(regRes.body.data.user.pinHash, undefined, 'pinHash must never be in registration response');

      // Inspect persisted datastore entity
      const userInDb = db.findUserByEmail('rohan@safesphere.org');
      assert.ok(userInDb, 'User must exist in db');
      assert.notEqual(userInDb.pin, '2468', 'Stored PIN must NOT be plain text');
      assert.match(userInDb.pin, /^\$2[ab]\$\d{2}\$/, 'Stored PIN must be a bcrypt hash');
      assert.equal(userInDb.pin, userInDb.pinHash, 'Both pin and pinHash should hold bcrypt hash');
      assert.equal(bcrypt.compareSync('2468', userInDb.pin), true, 'bcrypt compare must verify against stored PIN');

      // Login with valid PIN
      const loginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'rohan@safesphere.org',
          pin: '2468'
        }
      });

      assert.equal(loginRes.status, 200);
      assert.equal(loginRes.body.success, true);
      assert.ok(loginRes.body.data.accessToken);
      assert.equal(loginRes.body.data.user.email, 'rohan@safesphere.org');
      assert.equal(loginRes.body.data.user.pin, undefined);
      assert.equal(loginRes.body.data.user.pinHash, undefined);

      // Login with incorrect PIN
      const badLoginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'rohan@safesphere.org',
          pin: '1111'
        }
      });

      assert.equal(badLoginRes.status, 401);
      assert.equal(badLoginRes.body.error.code, 'INVALID_PIN');
    });

    it('persists bcrypt hash for 6-digit PIN on registration and authenticates via login-pin', async () => {
      const payload = {
        name: 'Meera Patel',
        email: 'meera@safesphere.org',
        phone: '+91 9822334455',
        password: 'MeeraPassword2026!',
        pin: '135790'
      };

      const regRes = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(regRes.status, 201);
      assert.equal(regRes.body.data.user.hasPin, true);

      const userInDb = db.findUserByEmail('meera@safesphere.org');
      assert.match(userInDb.pin, /^\$2[ab]\$\d{2}\$/);
      assert.equal(bcrypt.compareSync('135790', userInDb.pin), true);

      // Login with 6-digit PIN
      const loginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'meera@safesphere.org',
          pin: '135790'
        }
      });
      assert.equal(loginRes.status, 200);
    });

    it('registers user without PIN when PIN is not provided and rejects PIN login', async () => {
      const payload = {
        name: 'No Pin User',
        email: 'nopin@safesphere.org',
        phone: '+91 9833445566',
        password: 'Password2026!'
      };

      const regRes = await serverHarness.request('/api/v1/auth/register', {
        method: 'POST',
        body: payload
      });

      assert.equal(regRes.status, 201);
      assert.equal(regRes.body.data.user.hasPin, false);

      const userInDb = db.findUserByEmail('nopin@safesphere.org');
      assert.equal(userInDb.pin, null);
      assert.equal(userInDb.pinHash, null);

      const pinLoginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'nopin@safesphere.org',
          pin: '1234'
        }
      });
      assert.equal(pinLoginRes.status, 401);
      assert.equal(pinLoginRes.body.error.code, 'INVALID_PIN_CREDENTIALS');
    });

    it('demo user has bcrypt PIN hash in seed data and authenticates with 1234', async () => {
      const demoUserInDb = db.findUserByEmail('demo@safesphere.org');
      assert.ok(demoUserInDb);
      assert.match(demoUserInDb.pin, /^\$2[ab]\$\d{2}\$/, 'Demo user PIN in seedData must be a bcrypt hash');
      assert.equal(demoUserInDb.pin, demoUserInDb.pinHash);
      assert.equal(bcrypt.compareSync('1234', demoUserInDb.pin), true);

      const pinLoginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'demo@safesphere.org',
          pin: '1234'
        }
      });
      assert.equal(pinLoginRes.status, 200);
      assert.equal(pinLoginRes.body.data.user.hasPin, true);
    });

    it('maintains backwards compatibility fallback for legacy unhashed PIN mock objects', async () => {
      // Create a legacy mock user with plain text PIN
      const legacyUser = createUser({
        name: 'Legacy User',
        email: 'legacy@safesphere.org',
        phone: '+91 9844556677',
        passwordHash: bcrypt.hashSync('LegacyPass2026!', 8),
        pin: '5678' // unhashed string
      });
      db.saveUser(legacyUser);

      const pinLoginRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'legacy@safesphere.org',
          pin: '5678'
        }
      });
      assert.equal(pinLoginRes.status, 200, 'Legacy plain-text PIN fallback should succeed');

      // Invalid PIN still fails
      const badPinRes = await serverHarness.request('/api/v1/auth/login-pin', {
        method: 'POST',
        body: {
          emailOrPhone: 'legacy@safesphere.org',
          pin: '0000'
        }
      });
      assert.equal(badPinRes.status, 401);
    });
  });

  // ===========================================================================
  // 4. User Model Sanitization Tests
  // ===========================================================================
  describe('User Model Sanitization (toSafeUser)', () => {
    it('toSafeUser never exposes passwordHash, pin, or pinHash', () => {
      const user = createUser({
        name: 'Sanitize Test',
        email: 'sanitize@safesphere.org',
        phone: '+91 9999999999',
        passwordHash: '$2a$10$somelonghashherenotexposed',
        pinHash: '$2a$10$somepinhashherenotexposed'
      });

      const safe = toSafeUser(user);
      assert.equal(safe.passwordHash, undefined);
      assert.equal(safe.pin, undefined);
      assert.equal(safe.pinHash, undefined);
      assert.equal(safe.hasPin, true);
    });
  });
});
