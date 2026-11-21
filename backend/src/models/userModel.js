/**
 * User Entity Model
 * SafeSphere user representation, schema validator, and sanitization helper.
 */

const crypto = require('crypto');

function generateUserId() {
  return `usr_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

function normalizeEmail(email) {
  return (email || '').trim().toLowerCase();
}

function normalizePhone(phone) {
  return (phone || '').trim();
}

function createUser({
  id = generateUserId(),
  name,
  email,
  phone,
  role = 'citizen',
  passwordHash,
  pin = null,
  pinHash = null,
  biometricToken = null,
  biometricsEnabled = false,
  emergencyContacts = [],
  isActive = true,
  reputationScore = 0,
  strikes = 0,
  banned = false,
  aadhaarLast4Salt = null,
  aadhaarLast4Hash = null,
  createdAt = new Date().toISOString(),
  updatedAt = new Date().toISOString()
}) {
  const resolvedPin = pinHash || pin || null;
  return {
    id,
    name: (name || '').trim(),
    email: normalizeEmail(email),
    phone: normalizePhone(phone),
    role: (role || '').trim(),
    passwordHash,
    pin: resolvedPin ? String(resolvedPin).trim() : null,
    pinHash: resolvedPin ? String(resolvedPin).trim() : null,
    biometricToken: biometricToken ? String(biometricToken).trim() : null,
    biometricsEnabled: Boolean(biometricsEnabled),
    emergencyContacts: Array.isArray(emergencyContacts) ? emergencyContacts : [],
    isActive: Boolean(isActive),
    reputationScore: Number(reputationScore || 0),
    strikes: Number(strikes || 0),
    banned: Boolean(banned),
    aadhaarLast4Salt,
    aadhaarLast4Hash,
    createdAt,
    updatedAt
  };
}

function toSafeUser(user) {
  if (!user) return null;
  const reputationScore = Number(user.reputationScore || 0);
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    role: user.role || 'citizen',
    hasPin: Boolean(user.pin || user.pinHash),
    biometricsEnabled: Boolean(user.biometricsEnabled),
    emergencyContacts: user.emergencyContacts || [],
    isActive: user.isActive,
    reputationScore,
    trustedReporter: reputationScore >= 50,
    strikes: Number(user.strikes || 0),
    banned: Boolean(user.banned),
    aadhaarLinked: Boolean(user.aadhaarLast4Hash),
    createdAt: user.createdAt,
    updatedAt: user.updatedAt
  };
}

module.exports = {
  createUser,
  toSafeUser,
  generateUserId,
  normalizeEmail,
  normalizePhone
};
