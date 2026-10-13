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
  passwordHash,
  pin = null,
  biometricToken = null,
  biometricsEnabled = false,
  emergencyContacts = [],
  isActive = true,
  createdAt = new Date().toISOString(),
  updatedAt = new Date().toISOString()
}) {
  return {
    id,
    name: (name || '').trim(),
    email: normalizeEmail(email),
    phone: normalizePhone(phone),
    passwordHash,
    pin: pin ? String(pin).trim() : null,
    biometricToken: biometricToken ? String(biometricToken).trim() : null,
    biometricsEnabled: Boolean(biometricsEnabled),
    emergencyContacts: Array.isArray(emergencyContacts) ? emergencyContacts : [],
    isActive: Boolean(isActive),
    createdAt,
    updatedAt
  };
}

function toSafeUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    hasPin: Boolean(user.pin),
    biometricsEnabled: Boolean(user.biometricsEnabled),
    emergencyContacts: user.emergencyContacts || [],
    isActive: user.isActive,
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
