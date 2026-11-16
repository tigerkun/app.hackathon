/**
 * Tracking Service
 * Business logic for live guardian tracking sessions and breadcrumb telemetry.
 */

const { db } = require('../data/store');
const { createTrackingSession } = require('../models/trackingModel');

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
  const shareUrl = `${cleanBase}/?session=${encodeURIComponent(session.id)}`;

  return {
    sessionId: session.id,
    token: session.token,
    shareUrl,
    expiresAt: session.expiresAt,
    session
  };
}

function getTrackingSession(sessionId) {
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

  return session;
}

function recordPing({
  sessionId,
  latitude,
  longitude,
  speed,
  battery,
  accuracy,
  timestamp
}) {
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

  const pingPoint = {
    latitude: Number(latitude),
    longitude: Number(longitude),
    speed: speed !== undefined && speed !== null ? Number(speed) : 0,
    battery: battery !== undefined && battery !== null ? Number(battery) : null,
    accuracy: accuracy !== undefined && accuracy !== null ? Number(accuracy) : null,
    timestamp: timestamp ? String(timestamp) : new Date().toISOString()
  };

  const updatedSession = db.addTrackingBreadcrumb(sessionId, pingPoint);

  return {
    sessionId,
    currentLocation: pingPoint,
    pointCount: updatedSession.breadcrumbs.length,
    session: updatedSession
  };
}

function terminateTrackingSession(sessionId, reason = null) {
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
  isValidCoordinate
};
