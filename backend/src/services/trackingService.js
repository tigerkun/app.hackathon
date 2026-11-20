/**
 * Tracking Service
 * Business logic for live guardian tracking sessions and breadcrumb telemetry.
 */

const crypto = require('crypto');
const { db } = require('../data/store');
const { createTrackingSession } = require('../models/trackingModel');

/**
 * Constant-time comparison of a provided tracking token against the session's
 * secret token. The session token IS the credential (guest/anonymous included).
 */
function safeTokenEquals(expected, provided) {
  if (expected === undefined || expected === null || provided === undefined || provided === null) {
    return false;
  }
  const a = Buffer.from(String(expected));
  const b = Buffer.from(String(provided));
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Throws a 401 error unless the provided token matches the session token.
 */
function assertTrackingToken(session, token) {
  if (token === undefined || token === null || token === '') {
    const error = new Error('A tracking token is required to access this tracking session');
    error.status = 401;
    error.code = 'MISSING_TRACKING_TOKEN';
    throw error;
  }
  if (!safeTokenEquals(session.token, token)) {
    const error = new Error('Invalid tracking token for this tracking session');
    error.status = 401;
    error.code = 'INVALID_TRACKING_TOKEN';
    throw error;
  }
}

/**
 * Non-throwing token validation used by the WebSocket layer.
 */
function isValidTrackingToken(sessionId, token) {
  const session = db.findTrackingSessionById(sessionId);
  if (!session) return false;
  return safeTokenEquals(session.token, token);
}

function isValidCoordinate(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) return false;
  const numLat = Number(lat);
  const numLng = Number(lng);
  if (Number.isNaN(numLat) || Number.isNaN(numLng)) return false;
  if (numLat < -90 || numLat > 90) return false;
  if (numLng < -180 || numLng > 180) return false;
  return true;
}

function createShareSession({
  userId,
  userName,
  latitude,
  longitude,
  accuracy,
  speed,
  battery,
  durationMinutes = 60,
  metadata = {},
  baseUrl = 'http://127.0.0.1:8080'
}) {
  if (latitude === undefined || longitude === undefined || latitude === null || longitude === null) {
    const error = new Error('GPS coordinates (latitude and longitude) are required to create a tracking session');
    error.status = 400;
    error.code = 'MISSING_COORDINATES';
    throw error;
  }

  if (!isValidCoordinate(latitude, longitude)) {
    const error = new Error('Latitude must be between -90 and 90 and longitude between -180 and 180');
    error.status = 400;
    error.code = 'INVALID_COORDINATES';
    throw error;
  }

  let finalUserName = userName;
  if (userId) {
    const user = db.findUserById(userId);
    if (user && user.name) {
      finalUserName = user.name;
    }
  }

  const session = createTrackingSession({
    userId,
    userName: finalUserName || 'SafeSphere Citizen',
    latitude,
    longitude,
    accuracy,
    speed,
    battery,
    durationMinutes: Math.max(1, Math.min(1440, Number(durationMinutes) || 60)), // 1 min to 24 hrs
    metadata
  });

  db.saveTrackingSession(session);

  const cleanBase = (baseUrl || 'http://127.0.0.1:8080').replace(/\/+$/, '');
  const shareUrl = `${cleanBase}/?session=${encodeURIComponent(session.id)}&token=${encodeURIComponent(session.token)}`;

  return {
    sessionId: session.id,
    token: session.token,
    shareUrl,
    expiresAt: session.expiresAt,
    session
  };
}

const MAX_BREADCRUMBS_PER_SESSION = 500;

function getTrackingSession(sessionId, token) {
  if (!sessionId) {
    const error = new Error('sessionId is required');
    error.status = 400;
    error.code = 'MISSING_SESSION_ID';
    throw error;
  }

  const session = db.findTrackingSessionById(sessionId);
  if (!session) {
    const error = new Error(`Tracking session '${sessionId}' not found`);
    error.status = 404;
    error.code = 'SESSION_NOT_FOUND';
    throw error;
  }

  assertTrackingToken(session, token);

  if (Array.isArray(session.breadcrumbs) && session.breadcrumbs.length > MAX_BREADCRUMBS_PER_SESSION) {
    session.breadcrumbs = session.breadcrumbs.slice(-MAX_BREADCRUMBS_PER_SESSION);
  }

  return session;
}

function recordPing(arg1, arg2, arg3) {
  let sessionId, latitude, longitude, speed, battery, accuracy, timestamp, token;
  if (typeof arg1 === 'object' && arg1 !== null) {
    ({ sessionId, latitude, longitude, speed, battery, accuracy, timestamp, token } = arg1);
  } else {
    sessionId = arg1;
    if (typeof arg2 === 'object' && arg2 !== null) {
      ({ latitude, longitude, speed, battery, accuracy, timestamp } = arg2);
    }
    token = arg3;
  }

  if (!sessionId) {
    const error = new Error('sessionId is required for location ping');
    error.status = 400;
    error.code = 'MISSING_SESSION_ID';
    throw error;
  }

  if (latitude === undefined || longitude === undefined || latitude === null || longitude === null) {
    const error = new Error('latitude and longitude are required for location ping');
    error.status = 400;
    error.code = 'MISSING_COORDINATES';
    throw error;
  }

  if (!isValidCoordinate(latitude, longitude)) {
    const error = new Error('Latitude must be between -90 and 90 and longitude between -180 and 180');
    error.status = 400;
    error.code = 'INVALID_COORDINATES';
    throw error;
  }

  const session = db.findTrackingSessionById(sessionId);
  if (!session) {
    const error = new Error(`Tracking session '${sessionId}' not found`);
    error.status = 404;
    error.code = 'SESSION_NOT_FOUND';
    throw error;
  }

  assertTrackingToken(session, token);

  if (session.status === 'ended') {
    const error = new Error('Cannot append ping to an ended tracking session');
    error.status = 400;
    error.code = 'SESSION_ENDED';
    throw error;
  }

  if (session.status === 'expired' || (session.expiresAt && new Date(session.expiresAt) < new Date())) {
    const error = new Error('Cannot append ping to an expired tracking session');
    error.status = 400;
    error.code = 'SESSION_EXPIRED';
    throw error;
  }

  const nowIso = new Date().toISOString();
  session.lastActivityAt = nowIso;
  session.lastPingAt = nowIso;

  const pingPoint = {
    latitude: Number(latitude),
    longitude: Number(longitude),
    speed: speed !== undefined && speed !== null ? Number(speed) : 0,
    battery: battery !== undefined && battery !== null ? Number(battery) : null,
    accuracy: accuracy !== undefined && accuracy !== null ? Number(accuracy) : null,
    timestamp: timestamp ? String(timestamp) : nowIso
  };

  // Cap breadcrumbs to 500 entries per session (FIFO) to prevent unbounded memory growth
  if (Array.isArray(session.breadcrumbs) && session.breadcrumbs.length >= MAX_BREADCRUMBS_PER_SESSION) {
    session.breadcrumbs = session.breadcrumbs.slice(-(MAX_BREADCRUMBS_PER_SESSION - 1));
    db.saveTrackingSession(session);
  }

  const updatedSession = db.addTrackingBreadcrumb(sessionId, pingPoint);
  if (Array.isArray(updatedSession.breadcrumbs) && updatedSession.breadcrumbs.length > MAX_BREADCRUMBS_PER_SESSION) {
    updatedSession.breadcrumbs = updatedSession.breadcrumbs.slice(-MAX_BREADCRUMBS_PER_SESSION);
    db.saveTrackingSession(updatedSession);
  }

  return {
    sessionId,
    currentLocation: pingPoint,
    pointCount: updatedSession.breadcrumbs.length,
    session: updatedSession
  };
}

function terminateTrackingSession(sessionId, reason = null, token) {
  if (!sessionId) {
    const error = new Error('sessionId is required to terminate tracking session');
    error.status = 400;
    error.code = 'MISSING_SESSION_ID';
    throw error;
  }

  const session = db.findTrackingSessionById(sessionId);
  if (!session) {
    const error = new Error(`Tracking session '${sessionId}' not found`);
    error.status = 404;
    error.code = 'SESSION_NOT_FOUND';
    throw error;
  }

  assertTrackingToken(session, token);

  const updated = db.updateTrackingSession(sessionId, {
    status: 'ended',
    endedAt: new Date().toISOString(),
    endReason: reason || 'Terminated by user'
  });

  return updated;
}

module.exports = {
  createShareSession,
  getTrackingSession,
  recordPing,
  terminateTrackingSession,
  isValidCoordinate,
  isValidTrackingToken,
  assertTrackingToken,
  safeTokenEquals
};
