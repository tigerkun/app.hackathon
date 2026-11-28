/**
 * Env-Gated Admin Bootstrap Service
 *
 * Strictly opt-in via environment variables (no hardcoded credentials,
 * no HTTP promotion backdoor, no secret logging). Intended for provisioning
 * or verifying a moderator/admin account in production when DEMO_MODE=false.
 *
 * Env vars:
 *   BOOTSTRAP_ADMIN_EMAIL     Required to activate
 *   BOOTSTRAP_ADMIN_PASSWORD  Required to activate (>= 8 chars)
 *   BOOTSTRAP_ADMIN_PHONE     Required when creating a new user
 *   BOOTSTRAP_ADMIN_NAME      Optional display name (default: 'SafeSphere Moderator')
 *   BOOTSTRAP_ADMIN_PIN       Optional 4-6 digit quick PIN
 */

const bcrypt = require('bcryptjs');
const config = require('../config');
const { createUser, normalizeEmail, normalizePhone } = require('../models/userModel');
const { maskEmail } = require('./emailOtpService');

function bootstrapAdminIfConfigured(store) {
  if (!store) {
    return { action: 'skipped', reason: 'missing_store' };
  }

  const email = normalizeEmail(process.env.BOOTSTRAP_ADMIN_EMAIL || '');
  const password = String(process.env.BOOTSTRAP_ADMIN_PASSWORD || '');

  if (!email || !password) {
    return { action: 'inactive' };
  }

  if (password.length < 8) {
    console.warn('[bootstrap] BOOTSTRAP_ADMIN_PASSWORD must be at least 8 characters; skipping admin bootstrap.');
    return { action: 'skipped', reason: 'weak_password' };
  }

  const masked = maskEmail(email) || '[invalid-email]';
  const existing = store.findUserByEmail(email);

  if (existing) {
    if (existing.role === 'admin') {
      if (!existing.phoneVerified || !existing.isActive) {
        store.updateUser(existing.id, { phoneVerified: true, isActive: true });
      }
      return { action: 'noop', userId: existing.id };
    }

    // Anti-hijack guard: only promote an existing non-admin account if the
    // operator proves knowledge of the existing account password.
    if (!existing.passwordHash || !bcrypt.compareSync(password, existing.passwordHash)) {
      console.warn(`[bootstrap] Password mismatch for existing account ${masked}; refusing admin promotion.`);
      return { action: 'rejected', reason: 'password_mismatch' };
    }

    store.updateUser(existing.id, {
      role: 'admin',
      phoneVerified: true,
      isActive: true
    });
    console.log(`[bootstrap] Promoted existing account ${masked} to admin.`);
    return { action: 'promoted', userId: existing.id };
  }

  const phone = normalizePhone(process.env.BOOTSTRAP_ADMIN_PHONE || '');
  if (!phone || phone.length < 10) {
    console.warn(`[bootstrap] Valid BOOTSTRAP_ADMIN_PHONE is required to create admin ${masked}; skipping.`);
    return { action: 'skipped', reason: 'missing_phone' };
  }

  const phoneConflict = store.findUserByPhone(phone);
  if (phoneConflict) {
    console.warn(`[bootstrap] BOOTSTRAP_ADMIN_PHONE is already associated with another account; skipping admin creation for ${masked}.`);
    return { action: 'skipped', reason: 'phone_conflict' };
  }

  const name = (process.env.BOOTSTRAP_ADMIN_NAME || '').trim() || 'SafeSphere Moderator';
  const rawPin = (process.env.BOOTSTRAP_ADMIN_PIN || '').trim();
  const pinHash = /^\d{4,6}$/.test(rawPin) ? bcrypt.hashSync(rawPin, config.saltRounds) : null;
  const passwordHash = bcrypt.hashSync(password, config.saltRounds);

  const adminUser = createUser({
    name,
    email,
    phone,
    role: 'admin',
    passwordHash,
    pin: pinHash,
    pinHash,
    phoneVerified: true,
    isActive: true
  });

  const saved = store.saveUser(adminUser);
  console.log(`[bootstrap] Admin account created for ${masked}.`);
  return { action: 'created', userId: saved.id };
}

module.exports = {
  bootstrapAdminIfConfigured
};
