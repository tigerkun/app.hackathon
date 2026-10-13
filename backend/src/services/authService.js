/**
 * Auth Service
 * Pure business logic for user registration, multi-modal credential verification
 * (password, PIN, OTP, biometrics), session lifecycle, and token management.
 */

const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const config = require('../config');
const { db } = require('../data/store');
const { createUser, toSafeUser, normalizeEmail, normalizePhone } = require('../models/userModel');
const { createSession } = require('../models/sessionModel');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('./tokenService');
const { verifyOtp } = require('./otpService');

async function register({
  name,
  email,
  phone,
  password,
  pin,
  emergencyContact,
  emergencyContacts
}) {
  const normalizedEmail = normalizeEmail(email);
  const normalizedPhone = normalizePhone(phone);

  if (db.findUserByEmail(normalizedEmail) || db.findUserByPhone(normalizedPhone)) {
    const error = new Error('An account with this email or phone already exists');
    error.status = 409;
    error.code = 'USER_ALREADY_EXISTS';
    throw error;
  }

  const saltRounds = config.saltRounds;
  const passwordHash = bcrypt.hashSync(password, saltRounds);

  // Format emergency contacts
  let contactsList = [];
  if (Array.isArray(emergencyContacts)) {
    contactsList = emergencyContacts;
  } else if (emergencyContact && typeof emergencyContact === 'object') {
    contactsList = [
      {
        id: `cnt_${Date.now()}_${crypto.randomBytes(2).toString('hex')}`,
        name: emergencyContact.name || 'Emergency Contact',
        phone: emergencyContact.phone || '',
        relationship: emergencyContact.relationship || 'Emergency'
      }
    ];
  }

  const user = createUser({
    name,
    email: normalizedEmail,
    phone: normalizedPhone,
    passwordHash,
    pin: pin || null,
    emergencyContacts: contactsList,
    isActive: true
  });

  db.saveUser(user);

  // Create session and issue dual JWT tokens
  const session = createSession({
    userId: user.id,
    refreshToken: '',
    expiresInSeconds: config.refreshExpiresIn
  });

  const accessToken = signAccessToken(user, session.id);
  const refreshToken = signRefreshToken(user, session.id);

  session.refreshToken = refreshToken;
  db.saveSession(session);

  return {
    accessToken,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn,
    user: toSafeUser(user)
  };
}

async function login({ emailOrPhone, password, userAgent, ipAddress }) {
  const user = db.findUserByEmailOrPhone(emailOrPhone);
  if (!user) {
    const error = new Error('Invalid credentials provided');
    error.status = 401;
    error.code = 'INVALID_CREDENTIALS';
    throw error;
  }

  if (!user.isActive) {
    const error = new Error('Account is deactivated. Please contact support.');
    error.status = 403;
    error.code = 'ACCOUNT_DEACTIVATED';
    throw error;
  }

  const isPasswordValid = bcrypt.compareSync(password, user.passwordHash);
  if (!isPasswordValid) {
    const error = new Error('Invalid credentials provided');
    error.status = 401;
    error.code = 'INVALID_CREDENTIALS';
    throw error;
  }

  const session = createSession({
    userId: user.id,
    refreshToken: '',
    userAgent,
    ipAddress,
    expiresInSeconds: config.refreshExpiresIn
  });

  const accessToken = signAccessToken(user, session.id);
  const refreshToken = signRefreshToken(user, session.id);

  session.refreshToken = refreshToken;
  db.saveSession(session);

  return {
    accessToken,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn,
    user: toSafeUser(user)
  };
}

async function loginPin({ emailOrPhone, pin, userAgent, ipAddress }) {
  const user = db.findUserByEmailOrPhone(emailOrPhone);
  if (!user || !user.pin) {
    const error = new Error('Invalid credentials or PIN not configured');
    error.status = 401;
    error.code = 'INVALID_PIN_CREDENTIALS';
    throw error;
  }

  if (!user.isActive) {
    const error = new Error('Account is deactivated. Please contact support.');
    error.status = 403;
    error.code = 'ACCOUNT_DEACTIVATED';
    throw error;
  }

  const inputPin = String(pin).trim();
  if (user.pin !== inputPin) {
    const error = new Error('Invalid PIN provided');
    error.status = 401;
    error.code = 'INVALID_PIN';
    throw error;
  }

  const session = createSession({
    userId: user.id,
    refreshToken: '',
    userAgent,
    ipAddress,
    expiresInSeconds: config.refreshExpiresIn
  });

  const accessToken = signAccessToken(user, session.id);
  const refreshToken = signRefreshToken(user, session.id);

  session.refreshToken = refreshToken;
  db.saveSession(session);

  return {
    accessToken,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn,
    user: toSafeUser(user)
  };
}

async function verifyOtpAndLogin({ phone, otp, userAgent, ipAddress }) {
  const verifyResult = verifyOtp(phone, otp);

  const user = db.findUserByPhone(verifyResult.phone);
  if (!user) {
    // New phone verified receipt for pending registration
    const phoneVerifiedToken = `pvt_${Date.now()}_${crypto.randomBytes(16).toString('hex')}`;
    return {
      verified: true,
      phone: verifyResult.phone,
      phoneVerifiedToken
    };
  }

  if (!user.isActive) {
    const error = new Error('Account is deactivated. Please contact support.');
    error.status = 403;
    error.code = 'ACCOUNT_DEACTIVATED';
    throw error;
  }

  const session = createSession({
    userId: user.id,
    refreshToken: '',
    userAgent,
    ipAddress,
    expiresInSeconds: config.refreshExpiresIn
  });

  const accessToken = signAccessToken(user, session.id);
  const refreshToken = signRefreshToken(user, session.id);

  session.refreshToken = refreshToken;
  db.saveSession(session);

  return {
    verified: true,
    accessToken,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn,
    user: toSafeUser(user)
  };
}

async function refreshSession(refreshToken) {
  if (!refreshToken) {
    const error = new Error('Refresh token is required');
    error.status = 400;
    error.code = 'MISSING_REFRESH_TOKEN';
    throw error;
  }

  verifyRefreshToken(refreshToken);

  const session = db.findSessionByRefreshToken(refreshToken);
  if (!session || !session.isValid) {
    const error = new Error('Invalid, expired, or revoked refresh token');
    error.status = 401;
    error.code = 'INVALID_SESSION';
    throw error;
  }

  const user = db.findUserById(session.userId);
  if (!user || !user.isActive) {
    const error = new Error('User not found or account deactivated');
    error.status = 401;
    error.code = 'USER_INACTIVE';
    throw error;
  }

  const newAccessToken = signAccessToken(user, session.id);
  db.updateSession(session.id, { lastUsedAt: new Date().toISOString() });

  return {
    accessToken: newAccessToken,
    refreshToken: session.refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn
  };
}

async function logout(sessionId, optionalRefreshToken) {
  let invalidated = false;
  if (sessionId) {
    invalidated = db.invalidateSession(sessionId) || invalidated;
  }
  if (optionalRefreshToken) {
    const session = db.findSessionByRefreshToken(optionalRefreshToken);
    if (session) {
      invalidated = db.invalidateSession(session.id) || invalidated;
    }
  }
  return true;
}

async function registerBiometrics(userId, biometricToken) {
  const user = db.findUserById(userId);
  if (!user) {
    const error = new Error('User not found');
    error.status = 404;
    error.code = 'USER_NOT_FOUND';
    throw error;
  }

  const updated = db.updateUser(userId, {
    biometricToken: String(biometricToken).trim(),
    biometricsEnabled: true
  });

  return toSafeUser(updated);
}

async function loginBiometrics({ biometricToken, userAgent, ipAddress }) {
  if (!biometricToken) {
    const error = new Error('Biometric token is required');
    error.status = 400;
    error.code = 'MISSING_BIOMETRIC_TOKEN';
    throw error;
  }

  const user = db.findUserByBiometricToken(biometricToken);
  if (!user || !user.isActive) {
    const error = new Error('Invalid biometric token or unregistered device');
    error.status = 401;
    error.code = 'INVALID_BIOMETRICS';
    throw error;
  }

  const session = createSession({
    userId: user.id,
    refreshToken: '',
    userAgent,
    ipAddress,
    expiresInSeconds: config.refreshExpiresIn
  });

  const accessToken = signAccessToken(user, session.id);
  const refreshToken = signRefreshToken(user, session.id);

  session.refreshToken = refreshToken;
  db.saveSession(session);

  return {
    accessToken,
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: config.jwtExpiresIn,
    user: toSafeUser(user)
  };
}

module.exports = {
  register,
  login,
  loginPin,
  verifyOtpAndLogin,
  refreshSession,
  logout,
  registerBiometrics,
  loginBiometrics
};
