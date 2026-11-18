/**
 * SOS Service
 * Emergency alert handling, escalation, and resolution workflow.
 */

const { db } = require('../data/store');
const { createAlert } = require('../models/alertModel');
const crypto = require('crypto');

function hashToken(token) {
  if (!token) return null;
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function triggerSos({
  userId,
  userName,
  userPhone,
  latitude,
  longitude,
  accuracy,
  batteryLevel,
  alertType = 'CRITICAL_SOS',
  notes
}) {
  if (latitude === undefined || longitude === undefined || latitude === null || longitude === null) {
    const error = new Error('GPS latitude and longitude are required to trigger SOS');
    error.status = 400;
    error.code = 'MISSING_COORDINATES';
    throw error;
  }

  // Look up user emergency contacts count
  let contactsNotified = 0;
  let finalUserName = userName;
  let finalUserPhone = userPhone;

  if (userId) {
    const user = db.findUserById(userId);
    if (user) {
      // NOTE: contactsNotified indicates actual dispatched notifications.
      // In local mode without SMS/Twilio API keys configured, this remains 0 until real SMS gateway is wired.
      // TODO(REAL_SMS_GATEWAY): Integrate Twilio / AWS SNS SMS dispatch for user.emergencyContacts
      contactsNotified = 0;
      if (!finalUserName) finalUserName = user.name;
      if (!finalUserPhone) finalUserPhone = user.phone;
    }
  }

  const resolveToken = crypto.randomBytes(24).toString('base64url');

  const alert = createAlert({
    userId: userId || 'anonymous',
    userName: finalUserName || 'SafeSphere Citizen',
    userPhone: finalUserPhone || '',
    latitude: Number(latitude),
    longitude: Number(longitude),
    accuracy: accuracy !== undefined ? Number(accuracy) : null,
    batteryLevel: batteryLevel !== undefined ? Number(batteryLevel) : null,
    alertType: String(alertType || 'CRITICAL_SOS'),
    status: 'active',
    emergencyContactsNotified: contactsNotified,
    notes: notes || null,
    resolveTokenHash: hashToken(resolveToken)
  });

  db.saveAlert(alert);
  alert.resolveToken = resolveToken;
  return alert;
}

function getActiveAlerts() {
  return db.getActiveAlerts();
}

function getAllAlerts() {
  return db.getAllAlerts();
}

function getAlertById(alertId) {
  const alert = db.findAlertById(alertId);
  if (!alert) {
    const error = new Error('SOS alert not found');
    error.status = 404;
    error.code = 'ALERT_NOT_FOUND';
    throw error;
  }
  return alert;
}

function resolveSos(alertId, notes = null) {
  const existing = db.findAlertById(alertId);
  if (!existing) {
    const error = new Error('SOS alert not found');
    error.status = 404;
    error.code = 'ALERT_NOT_FOUND';
    throw error;
  }

  const updated = db.updateAlert(alertId, {
    status: 'resolved',
    resolvedAt: new Date().toISOString(),
    notes: notes || existing.notes
  });

  return updated;
}

module.exports = {
  triggerSos,
  getActiveAlerts,
  getAllAlerts,
  getAlertById,
  resolveSos
};
