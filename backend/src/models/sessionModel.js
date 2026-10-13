/**
 * Session Entity Model
 * SafeSphere user session representation for tracking refresh tokens and active client devices.
 */

const crypto = require('crypto');

function generateSessionId() {
  return `ses_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

function createSession({
  id = generateSessionId(),
  userId,
  refreshToken,
  userAgent = 'unknown',
  ipAddress = '127.0.0.1',
  expiresInSeconds = 604800, // 7 days
  isValid = true,
  createdAt = new Date().toISOString(),
  lastUsedAt = new Date().toISOString()
}) {
  const expiresAt = new Date(Date.now() + expiresInSeconds * 1000).toISOString();
  return {
    id,
    userId,
    refreshToken,
    userAgent,
    ipAddress,
    expiresAt,
    isValid: Boolean(isValid),
    createdAt,
    lastUsedAt
  };
}

module.exports = {
  createSession,
  generateSessionId
};
