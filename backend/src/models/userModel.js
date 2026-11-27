/**
 * User Entity Model
 * SafeSphere user representation, schema validator, and sanitization helper.
 */

const crypto = require('crypto');

function generateUserId() {
  return `usr_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

// M3: short unique public Safe ID (e.g. SF-7X4K-2Q) — used to send
// connection requests without exposing email/phone.
function generateSafeId() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
  const pick = (n) => Array.from(crypto.randomBytes(n))
    .map((b) => alphabet[b % alphabet.length]).join('');
  return `SF-${pick(4)}-${pick(2)}`;
}

function normalizeEmail(email) {
  return (email || '').trim().toLowerCase();
}

function normalizePhone(phone) {
  // Canonical form: digits only, Indian mobile normalized to 91XXXXXXXXXX.
  // '9876543210', '+91 98765-43210', '091-9876543210' must all resolve to the
  // same account — raw trimmed text allowed duplicate accounts per SIM and
  // broke forgot-PIN/OTP lookups for differently-formatted stored numbers.
  const digits = String(phone || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  return digits;
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
  phoneVerified = false,
  lastKnownLat = null,
  lastKnownLng = null,
  lastSeenAt = null,
  safeId = generateSafeId(),
  createdAt = new Date().toISOString(),
  updatedAt = new Date().toISOString()
}) {
  const resolvedPin = pinHash || pin || null;
  return {
    id,
    safeId,
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
    phoneVerified: Boolean(phoneVerified),
    lastKnownLat: lastKnownLat !== null && lastKnownLat !== undefined ? Number(lastKnownLat) : null,
    lastKnownLng: lastKnownLng !== null && lastKnownLng !== undefined ? Number(lastKnownLng) : null,
    lastSeenAt: lastSeenAt ?? null,
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
    safeId: user.safeId || null,
    hasPin: Boolean(user.pin || user.pinHash),
    biometricsEnabled: Boolean(user.biometricsEnabled),
    emergencyContacts: user.emergencyContacts || [],
    isActive: user.isActive,
    reputationScore,
    trustedReporter: reputationScore >= 50,
    strikes: Number(user.strikes || 0),
    banned: Boolean(user.banned),
    aadhaarLinked: Boolean(user.aadhaarLast4Hash),
    phoneVerified: Boolean(user.phoneVerified),
    createdAt: user.createdAt,
    updatedAt: user.updatedAt
  };
}

/**
 * Minimal projection for connection/trusted-circle counterparties.
 * Deliberately excludes email, phone, emergencyContacts, strikes, banned,
 * aadhaarLinked — pending or revoked connections must not leak PII.
 */
function toConnectionPeer(user) {
  if (!user) return null;
  return {
    id: user.id,
    name: user.name,
    safeId: user.safeId || null,
    role: user.role || 'citizen'
  };
}

module.exports = {
  createUser,
  toSafeUser,
  toConnectionPeer,
  generateUserId,
  generateSafeId,
  normalizeEmail,
  normalizePhone
};
