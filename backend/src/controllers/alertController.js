/**
 * Alert Controller
 * Handles real-time emergency SOS trigger, active alert broadcast, and resolution.
 */

const sosService = require('../services/sosService');

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
    const alerts = sosService.getActiveAlerts();

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
    const alerts = sosService.getAllAlerts();

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

    res.status(200).json({
      success: true,
      data: alert
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
