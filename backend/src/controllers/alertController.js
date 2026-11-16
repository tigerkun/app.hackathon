/**
 * Alert Controller
 * Handles real-time emergency SOS trigger, active alert broadcast, and resolution.
 */

const sosService = require('../services/sosService');
const { toSafeAlert } = require('../models/alertModel');

// Lazy-reference broadcastSosAlert to avoid circular dependency issues at boot
function getBroadcastHelper() {
  try {
    const serverModule = require('../server');
    return serverModule.broadcastSosAlert;
  } catch (_) {
    return null;
  }
}

function trigger(req, res, next) {
  try {
    const body = req.body || {};
    const latitude = body.latitude;
    const longitude = body.longitude;
    const accuracy = body.accuracy;
    const batteryLevel = body.batteryLevel !== undefined ? body.batteryLevel : body.battery_level;
    const alertType = body.alertType || body.alert_type || 'CRITICAL_SOS';
    const notes = body.notes;

    const userId = req.user ? req.user.id : (body.userId || body.user_id || null);
    const userName = req.user ? req.user.name : (body.userName || body.user_name || 'SafeSphere Citizen');
    const userPhone = req.user ? req.user.phone : (body.userPhone || body.user_phone || '');

    const alert = sosService.triggerSos({
      userId,
      userName,
      userPhone,
      latitude,
      longitude,
      accuracy,
      batteryLevel,
      alertType,
      notes
    });

    // Wire real SOS alert broadcast across active WebSocket monitors and dispatchers.
    // The WS channel is unauthenticated, so broadcast the PII-masked view only.
    const broadcast = getBroadcastHelper();
    if (typeof broadcast === 'function') {
      broadcast(toSafeAlert(alert, false));
    }

    res.status(201).json({
      success: true,
      message: 'Emergency SOS alert triggered successfully',
      data: alert,
      ...alert
    });
  } catch (err) {
    next(err);
  }
}

function active(req, res, next) {
  try {
    const rawAlerts = sosService.getActiveAlerts();
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));
    const alerts = rawAlerts.map(a => {
      const isOwner = req.user && req.user.id === a.userId;
      return toSafeAlert(a, isOwner || isPrivileged);
    });

    res.status(200).json({
      success: true,
      count: alerts.length,
      data: alerts
    });
  } catch (err) {
    next(err);
  }
}

function list(req, res, next) {
  try {
    const rawAlerts = sosService.getAllAlerts();
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));
    const alerts = rawAlerts.map(a => {
      const isOwner = req.user && req.user.id === a.userId;
      return toSafeAlert(a, isOwner || isPrivileged);
    });

    res.status(200).json({
      success: true,
      count: alerts.length,
      data: alerts
    });
  } catch (err) {
    next(err);
  }
}

function getById(req, res, next) {
  try {
    const { id } = req.params;
    const alert = sosService.getAlertById(id);
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));
    const isOwner = req.user && req.user.id === alert.userId;

    res.status(200).json({
      success: true,
      data: toSafeAlert(alert, isOwner || isPrivileged)
    });
  } catch (err) {
    next(err);
  }
}

function resolve(req, res, next) {
  try {
    const alertId = req.params.id || (req.body && (req.body.id || req.body.alertId || req.body.alert_id));
    const notes = req.body && req.body.notes;

    if (!alertId) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_ALERT_ID',
          message: 'SOS alert ID is required to resolve alert',
          details: []
        }
      });
    }

    const existing = sosService.getAlertById(alertId);

    // Alerts owned by a registered user may ONLY be resolved by that owner or an admin role.
    // Anonymous/guest alerts carry no owner identity and remain resolvable without auth
    // (the guest who triggered them has no account to authenticate with).
    if (existing.userId && existing.userId !== 'anonymous') {
      if (!req.user) {
        return res.status(401).json({
          success: false,
          error: {
            code: 'UNAUTHORIZED_RESOLVE',
            message: 'Authentication is required to resolve this SOS alert',
            details: []
          }
        });
      }
      const isOwner = req.user.id === existing.userId;
      const isAdmin = req.user.role === 'admin' || req.user.role === 'first_responder';
      if (!isOwner && !isAdmin) {
        return res.status(403).json({
          success: false,
          error: {
            code: 'FORBIDDEN_RESOLVE',
            message: 'You are not authorized to resolve this SOS alert',
            details: []
          }
        });
      }
    }

    const updated = sosService.resolveSos(alertId, notes);

    res.status(200).json({
      success: true,
      message: 'Emergency SOS alert resolved successfully',
      data: updated
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  trigger,
  active,
  list,
  getById,
  resolve
};
