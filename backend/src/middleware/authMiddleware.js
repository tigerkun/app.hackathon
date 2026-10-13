/**
 * Auth Middleware
 * JWT Bearer token authentication and session state verification.
 */

const { verifyAccessToken } = require('../services/tokenService');
const { db } = require('../data/store');
const { toSafeUser } = require('../models/userModel');

function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Missing or invalid authorization token',
        details: []
      }
    });
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    return res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authorization token cannot be empty',
        details: []
      }
    });
  }

  try {
    const payload = verifyAccessToken(token);

    // Verify Session validity if sessionId is present
    if (payload.sessionId) {
      const session = db.findSessionById(payload.sessionId);
      if (session && !session.isValid) {
        return res.status(401).json({
          success: false,
          error: {
            code: 'SESSION_REVOKED',
            message: 'Session has been invalidated or logged out',
            details: []
          }
        });
      }
    }

    // Verify User existence and active status
    const user = db.findUserById(payload.sub);
    if (!user || !user.isActive) {
      return res.status(401).json({
        success: false,
        error: {
          code: 'USER_INACTIVE',
          message: 'User account not found or deactivated',
          details: []
        }
      });
    }

    req.user = toSafeUser(user);
    req.userId = user.id;
    req.sessionId = payload.sessionId;
    next();
  } catch (err) {
    return res.status(401).json({
      success: false,
      error: {
        code: err.code || 'INVALID_TOKEN',
        message: err.message || 'Invalid or expired authorization token',
        details: []
      }
    });
  }
}

function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    req.user = null;
    req.userId = null;
    return next();
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    req.user = null;
    req.userId = null;
    return next();
  }

  try {
    const payload = verifyAccessToken(token);
    const user = db.findUserById(payload.sub);
    if (user && user.isActive) {
      req.user = toSafeUser(user);
      req.userId = user.id;
      req.sessionId = payload.sessionId;
    } else {
      req.user = null;
      req.userId = null;
    }
  } catch (e) {
    req.user = null;
    req.userId = null;
  }

  next();
}

module.exports = {
  requireAuth,
  optionalAuth
};
