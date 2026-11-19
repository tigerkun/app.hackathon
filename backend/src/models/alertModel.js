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
  notes = null,
  resolveTokenHash = null
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
    notes: notes ? String(notes).trim() : null,
    resolveTokenHash: resolveTokenHash || null
  };
}

function toSafeAlert(alert, isOwnerOrAdmin = false) {
  if (!alert) return null;
  if (isOwnerOrAdmin) {
    const safe = { ...alert };
    delete safe.resolveTokenHash;
    return safe;
  }

  // Mask sensitive victim PII (phone number, exact user identification)
  let maskedPhone = '';
  if (alert.userPhone && alert.userPhone.length > 4) {
    maskedPhone = alert.userPhone.slice(0, 3) + '****' + alert.userPhone.slice(-2);
  }

  return {
    id: alert.id,
    userId: alert.userId === 'anonymous' ? 'anonymous' : 'protected_user',
    userName: alert.userName || 'SafeSphere Citizen',
    userPhone: maskedPhone,
    latitude: alert.latitude,
    longitude: alert.longitude,
    accuracy: alert.accuracy,
    batteryLevel: alert.batteryLevel,
    alertType: alert.alertType,
    status: alert.status,
    triggeredAt: alert.triggeredAt,
    resolvedAt: alert.resolvedAt,
    emergencyContactsNotified: alert.emergencyContactsNotified,
    notes: alert.notes
  };
}

module.exports = {
  createAlert,
  generateAlertId,
  toSafeAlert,
  VALID_ALERT_STATUSES
};
