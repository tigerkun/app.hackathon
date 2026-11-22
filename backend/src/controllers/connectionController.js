/**
 * Connection Controller
 * M3: HTTP envelope handlers for the account-to-account trusted circle.
 * All routes require auth (mounted behind requireAuth). Errors thrown by the
 * service carry { status, code } and are mapped into the standard envelope.
 */

const connectionService = require('../services/connectionService');
const { db } = require('../data/store');
const { toConnectionPeer } = require('../models/userModel');

function handleError(res, error) {
  const status = error.status || 500;
  if (status >= 500) console.error('[connectionController]', error);
  res.status(status).json({
    success: false,
    error: {
      code: error.code || 'INTERNAL_ERROR',
      message: error.message || 'Internal error',
      details: error.details
    }
  });
}

/** POST /api/v1/connections — send a request addressed by Safe ID. */
async function createConnection(req, res) {
  try {
    const { ownerSafeId, scopes, mode } = req.body || {};
    const result = connectionService.requestConnection({
      requester: req.user,
      ownerSafeId,
      scopes,
      mode: mode || 'sos_only'
    });
    res.status(201).json({ success: true, data: result });
  } catch (error) {
    handleError(res, error);
  }
}

/** GET /api/v1/connections/mine — both directions, decorated with counterpart names. */
async function getMyConnections(req, res) {
  try {
    const userId = req.user.id;
    const outgoing = db.listConnectionsByGrantee(userId).map((c) => ({
      ...c,
      counterpart: toConnectionPeer(db.findUserById(c.ownerId))
    }));
    const incoming = db.listConnectionsByOwner(userId).map((c) => {
      // Owner view: surface the grantee's latest "check on them" ping so the
      // feature delivers what the UI promises.
      const latest = c.status === 'active' ? db.getLatestConnectionCheckin(c.id) : null;
      const fromUser = latest ? db.findUserById(latest.fromUserId) : null;
      return {
        ...c,
        counterpart: toConnectionPeer(db.findUserById(c.granteeId)),
        lastCheckIn: latest
          ? { message: latest.message, at: latest.createdAt, fromName: fromUser ? fromUser.name : 'SafeSphere user' }
          : null
      };
    });
    res.json({
      success: true,
      data: {
        outgoing,   // requests I sent / people I can watch
        incoming,   // requests I received / people who can watch me
        pendingIncomingCount: incoming.filter((c) => c.status === 'pending').length
      }
    });
  } catch (error) {
    handleError(res, error);
  }
}

/** POST /api/v1/connections/:id/respond — owner accepts/declines; grantee can withdraw. */
async function respondToConnection(req, res) {
  try {
    const { accept } = req.body || {};
    const conn = connectionService.respondToConnection({
      connectionId: req.params.id,
      responder: req.user,
      accept: Boolean(accept)
    });
    res.json({ success: true, data: { connection: conn } });
  } catch (error) {
    handleError(res, error);
  }
}

/** POST /api/v1/connections/:id/revoke — either party, immediate. */
async function revokeConnection(req, res) {
  try {
    const conn = connectionService.revokeConnection({
      connectionId: req.params.id,
      responder: req.user
    });
    res.json({ success: true, data: { connection: conn } });
  } catch (error) {
    handleError(res, error);
  }
}

/** PATCH /api/v1/connections/:id/scopes — owner-only scope adjustment. */
async function updateScopes(req, res) {
  try {
    const conn = connectionService.updateScopes({
      connectionId: req.params.id,
      ownerId: req.user.id,
      scopes: (req.body || {}).scopes
    });
    res.json({ success: true, data: { connection: conn } });
  } catch (error) {
    handleError(res, error);
  }
}

/** POST /api/v1/connections/:id/ping — owner beacons a location point. */
async function pingLocation(req, res) {
  try {
    const { latitude, longitude, accuracy } = req.body || {};
    const lat = Number(latitude);
    const lng = Number(longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return res.status(400).json({
        success: false,
        error: { code: 'INVALID_COORDINATES', message: 'latitude/longitude must be valid coordinates.' }
      });
    }
    const location = connectionService.recordBeaconPing({
      connectionId: req.params.id,
      owner: req.user,
      latitude: lat,
      longitude: lng,
      accuracy: accuracy !== undefined && accuracy !== null ? Number(accuracy) : null
    });
    res.json({ success: true, data: { location } });
  } catch (error) {
    handleError(res, error);
  }
}

/** GET /api/v1/connections/:id/live — grantee reads the owner's latest beacon. */
async function getLiveLocation(req, res) {
  try {
    connectionService.verifyScopedAccess({
      connectionId: req.params.id,
      viewerId: req.user.id,
      requiredScope: 'location'
    });
    const location = db.getLatestConnectionLocation(req.params.id);
    res.json({
      success: true,
      data: {
        location,
        hasSignal: Boolean(location)
      }
    });
  } catch (error) {
    handleError(res, error);
  }
}

/** GET /api/v1/connections/:id/alerts — grantee reads the owner's recent alerts. */
async function getOwnerAlerts(req, res) {
  try {
    const conn = connectionService.verifyScopedAccess({
      connectionId: req.params.id,
      viewerId: req.user.id,
      requiredScope: 'nearby_alerts'
    });
    const alerts = db
      .getActiveAlerts()
      .filter((a) => a.userId === conn.ownerId)
      .map((a) => ({
        id: a.id,
        alertType: a.alertType,
        status: a.status,
        escalationLevel: a.escalationLevel,
        latitude: a.latitude,
        longitude: a.longitude,
        triggeredAt: a.triggeredAt
      }));
    res.json({ success: true, data: { alerts } });
  } catch (error) {
    handleError(res, error);
  }
}

/** GET /api/v1/connections/:id/status — grantee reads the owner's SOS status. */
async function getOwnerStatus(req, res) {
  try {
    const conn = connectionService.verifyScopedAccess({
      connectionId: req.params.id,
      viewerId: req.user.id,
      requiredScope: 'sos_status'
    });
    const owner = db.findUserById(conn.ownerId);
    const activeAlerts = db
      .getActiveAlerts()
      .filter((a) => a.userId === conn.ownerId);
    const activeTracking = db.getActiveTrackingSessionsByUser(conn.ownerId);
    res.json({
      success: true,
      data: {
        owner: { id: owner.id, name: owner.name, safeId: owner.safeId },
        sosActive: activeAlerts.length > 0,
        sosAlert: activeAlerts.length > 0 ? {
          id: activeAlerts[0].id,
          alertType: activeAlerts[0].alertType,
          escalationLevel: activeAlerts[0].escalationLevel,
          triggeredAt: activeAlerts[0].triggeredAt
        } : null,
        trackingActive: activeTracking.length > 0,
        trackingSessionId: activeTracking.length > 0 ? activeTracking[0].id : null
      }
    });
  } catch (error) {
    handleError(res, error);
  }
}

/** POST /api/v1/connections/:id/checkin — grantee "checks on" the owner. */
async function checkIn(req, res) {
  try {
    const result = connectionService.recordCheckIn({
      connectionId: req.params.id,
      viewer: req.user,
      message: (req.body || {}).message
    });
    res.json({ success: true, data: result });
  } catch (error) {
    handleError(res, error);
  }
}

module.exports = {
  createConnection,
  getMyConnections,
  respondToConnection,
  revokeConnection,
  updateScopes,
  pingLocation,
  getLiveLocation,
  getOwnerAlerts,
  getOwnerStatus,
  checkIn
};
