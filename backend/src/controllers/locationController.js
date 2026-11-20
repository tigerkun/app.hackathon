/**
 * Location Controller
 * REST API handlers for live guardian tracking sessions, coordinates pings, and retrieval.
 */

const trackingService = require('../services/trackingService');

/**
 * Extract the tracking session credential from the request.
 * Accepts `Authorization: Bearer <token>`, `?token=`, or `body.token`.
 * The session token IS the credential (guest/anonymous design).
 */
function extractTrackingToken(req) {
  const authHeader = req.headers && req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const bearer = authHeader.slice(7).trim();
    if (bearer) return bearer;
  }
  if (req.query && req.query.token) return String(req.query.token);
  if (req.body && req.body.token) return String(req.body.token);
  return null;
}

function shareSession(req, res, next) {
  try {
    const body = req.body || {};
    const latitude = body.latitude;
    const longitude = body.longitude;
    const accuracy = body.accuracy;
    const speed = body.speed;
    const battery = body.battery !== undefined ? body.battery : body.batteryLevel;
    const durationMinutes = body.durationMinutes || body.duration_minutes || 60;
    const metadata = body.metadata || {};

    let checkInIntervalMin = body.checkInIntervalMin !== undefined ? body.checkInIntervalMin : body.check_in_interval_min;
    if (checkInIntervalMin === undefined || checkInIntervalMin === null || checkInIntervalMin === '') {
      checkInIntervalMin = null;
    } else {
      if (typeof checkInIntervalMin === 'boolean') {
        const error = new Error('checkInIntervalMin must be an integer between 1 and 1440');
        error.status = 400;
        error.code = 'INVALID_CHECKIN_INTERVAL';
        throw error;
      }
      const parsedInterval = Number(checkInIntervalMin);
      if (!Number.isInteger(parsedInterval) || parsedInterval < 1 || parsedInterval > 1440) {
        const error = new Error('checkInIntervalMin must be an integer between 1 and 1440');
        error.status = 400;
        error.code = 'INVALID_CHECKIN_INTERVAL';
        throw error;
      }
      checkInIntervalMin = parsedInterval;
    }

    const checkInDeadline = checkInIntervalMin
      ? new Date(Date.now() + checkInIntervalMin * 60 * 1000).toISOString()
      : null;
    const missedCheckIns = 0;

    const userId = req.user ? req.user.id : (body.userId || body.user_id || null);
    const userName = req.user ? req.user.name : (body.userName || body.user_name || 'SafeSphere Citizen');

    const result = trackingService.createShareSession({
      userId,
      userName,
      latitude,
      longitude,
      accuracy,
      speed,
      battery,
      durationMinutes,
      checkInIntervalMin,
      checkInDeadline,
      missedCheckIns,
      metadata,
      baseUrl: body.baseUrl || 'http://127.0.0.1:8080'
    });

    res.status(201).json({
      success: true,
      message: 'Tracking session created successfully',
      sessionId: result.sessionId,
      token: result.token,
      shareUrl: result.shareUrl,
      expiresAt: result.expiresAt,
      data: {
        sessionId: result.sessionId,
        token: result.token,
        shareUrl: result.shareUrl,
        expiresAt: result.expiresAt,
        session: result.session
      }
    });
  } catch (err) {
    next(err);
  }
}

function getTrack(req, res, next) {
  try {
    const { sessionId } = req.params;
    const session = trackingService.getTrackingSession(sessionId, extractTrackingToken(req));

    const now = Date.now();
    const lastActivityMs = new Date(session.lastActivityAt || session.currentLocation?.timestamp || session.createdAt).getTime();
    const stallDetected = session.status === 'active' && (now - lastActivityMs > 120000);
    const stalledDurationSeconds = Math.max(0, Math.floor((now - lastActivityMs) / 1000));

    const lastActivityAt = session.lastActivityAt || session.currentLocation?.timestamp || session.createdAt;
    session.lastActivityAt = lastActivityAt;
    session.stallDetected = Boolean(stallDetected);
    session.stalledDurationSeconds = stalledDurationSeconds;

    res.status(200).json({
      success: true,
      data: {
        session,
        sessionId: session.id,
        userName: session.userName,
        status: session.status,
        currentLocation: session.currentLocation,
        breadcrumbs: session.breadcrumbs,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        lastActivityAt,
        lastPingAt: session.lastPingAt || null,
        stallDetected: Boolean(stallDetected),
        stalledDurationSeconds,
        checkInIntervalMin: session.checkInIntervalMin !== null && session.checkInIntervalMin !== undefined ? Number(session.checkInIntervalMin) : null,
        checkInDeadline: session.checkInDeadline ?? null,
        missedCheckIns: Number(session.missedCheckIns || 0)
      }
    });
  } catch (err) {
    next(err);
  }
}

function ping(req, res, next) {
  try {
    const body = req.body || {};
    const sessionId = body.sessionId || body.session_id;
    const latitude = body.latitude;
    const longitude = body.longitude;
    const speed = body.speed;
    const battery = body.battery !== undefined ? body.battery : body.batteryLevel;
    const accuracy = body.accuracy;
    const timestamp = body.timestamp;

    const result = trackingService.recordPing({
      sessionId,
      latitude,
      longitude,
      speed,
      battery,
      accuracy,
      timestamp,
      token: extractTrackingToken(req)
    });

    // Relay location update to active WebSocket guardian subscribers
    try {
      const { broadcastLocationUpdate } = require('../server');
      if (typeof broadcastLocationUpdate === 'function') {
        broadcastLocationUpdate(sessionId, result.currentLocation);
      }
    } catch (_) {}

    res.status(200).json({
      success: true,
      message: 'Location ping recorded',
      data: {
        sessionId: result.sessionId,
        currentLocation: result.currentLocation,
        pointCount: result.pointCount,
        timestamp: result.currentLocation.timestamp
      }
    });
  } catch (err) {
    next(err);
  }
}

function terminate(req, res, next) {
  try {
    const sessionId = req.params.sessionId || (req.body && (req.body.sessionId || req.body.session_id));
    const reason = req.body && req.body.reason;

    const session = trackingService.terminateTrackingSession(sessionId, reason, extractTrackingToken(req));

    // Relay stream termination to active WebSocket subscribers
    try {
      const { broadcastStreamTerminate } = require('../server');
      if (typeof broadcastStreamTerminate === 'function') {
        broadcastStreamTerminate(sessionId, reason);
      }
    } catch (_) {}

    res.status(200).json({
      success: true,
      message: 'Tracking session terminated',
      data: session
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  shareSession,
  getTrack,
  ping,
  terminate
};
