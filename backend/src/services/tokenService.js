/**
 * Token Service
 * Handles cryptographic JWT access and refresh token signing and verification.
 */

const jwt = require('jsonwebtoken');
const config = require('../config');

function signAccessToken(user, sessionId) {
  const payload = {
    sub: user.id,
    email: user.email,
    phone: user.phone,
    sessionId
  };

  return jwt.sign(payload, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn
  });
}

function signRefreshToken(user, sessionId) {
  const payload = {
    sub: user.id,
    sessionId
  };

  return jwt.sign(payload, config.refreshSecret, {
    expiresIn: config.refreshExpiresIn
  });
}

function verifyAccessToken(token) {
  try {
    return jwt.verify(token, config.jwtSecret);
  } catch (err) {
    const error = new Error(err.message === 'jwt expired' ? 'Token expired' : 'Invalid authorization token');
    error.status = 401;
    error.code = 'INVALID_TOKEN';
    throw error;
  }
}

function verifyRefreshToken(token) {
  try {
    return jwt.verify(token, config.refreshSecret);
  } catch (err) {
    const error = new Error(err.message === 'jwt expired' ? 'Refresh token expired' : 'Invalid refresh token');
    error.status = 401;
    error.code = 'INVALID_REFRESH_TOKEN';
    throw error;
  }
}

module.exports = {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken
};
