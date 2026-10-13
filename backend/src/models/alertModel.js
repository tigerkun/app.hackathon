/**
 * SOS Alert Entity Model
 * SafeSphere real-time emergency alert schema.
 */

const crypto = require('crypto');

function generateAlertId() {
  return `sos_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_ALERT_STATUSES = ['active', 'resolved', 'cancelled'];

function createAlert({
  id = generateAlertId(),
  userId,
  userName = 'SafeSphere Citizen',
  userPhone = '',
  latitude,
  longitude,
  accuracy = null,
  batteryLevel = null,
  alertType = 'CRITICAL_SOS',
  status = 'active',
  triggeredAt = new Date().toISOString(),
  resolvedAt = null,
  emergencyContactsNotified = 0,
  notes = null
}) {
  return {
    id,
    userId: String(userId),
    userName: String(userName),
    userPhone: String(userPhone),
    latitude: Number(latitude),
    longitude: Number(longitude),
    accuracy: accuracy !== null ? Number(accuracy) : null,
    batteryLevel: batteryLevel !== null ? Number(batteryLevel) : null,
    alertType: String(alertType || 'CRITICAL_SOS'),
    status: VALID_ALERT_STATUSES.includes(status) ? status : 'active',
    triggeredAt,
    resolvedAt: resolvedAt ? String(resolvedAt) : null,
    emergencyContactsNotified: Number(emergencyContactsNotified || 0),
    notes: notes ? String(notes).trim() : null
  };
}

module.exports = {
  createAlert,
  generateAlertId,
  VALID_ALERT_STATUSES
};
