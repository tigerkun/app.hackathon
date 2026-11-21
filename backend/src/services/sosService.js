/**
 * SOS Service
 * Emergency alert handling, escalation, and resolution workflow.
 */

const { db } = require('../data/store');
const { createAlert } = require('../models/alertModel');
const config = require('../config');
const crypto = require('crypto');

let watchdogInterval = null;

function getBroadcastHelpers() {
  try {
    const serverModule = require('../server');
    return {
      broadcastSosAlert: serverModule.broadcastSosAlert,
      broadcastSosEscalated: serverModule.broadcastSosEscalated
    };
  } catch (_) {
    return {};
  }
}

function tickEscalation({
  now = Date.now(),
  escalateAfterMs = config.escalateAfterMs,
  broadcastEscalation = null,
  broadcastAlert = null
} = {}) {
  const activeAlerts = db.getActiveAlerts();
  const escalated = [];
  const helpers = getBroadcastHelpers();
  const sendEscalated = broadcastEscalation || helpers.broadcastSosEscalated;
  const sendAlert = broadcastAlert || helpers.broadcastSosAlert;

  for (const alert of activeAlerts) {
    const currentLevel = Number(alert.escalationLevel || 0);
    if (currentLevel >= 3) continue;

    const triggeredMs = alert.triggeredAt ? new Date(alert.triggeredAt).getTime() : now;
    const elapsedMs = Math.max(0, now - triggeredMs);
    const thresholdMs = escalateAfterMs * (currentLevel + 1);

    if (elapsedMs >= thresholdMs) {
      const nextLevel = currentLevel + 1;
      const elapsedMin = Math.floor(elapsedMs / 60000);
      const updated = db.updateAlert(alert.id, { escalationLevel: nextLevel });
      escalated.push(updated);

      if (typeof sendEscalated === 'function') {
        sendEscalated({
          alertId: alert.id,
          level: nextLevel,
          elapsedMin
        });
      }

      if (typeof sendAlert === 'function') {
        const { toSafeAlert } = require('../models/alertModel');
        sendAlert(toSafeAlert(updated, false));
      }
    }
  }

  return escalated;
}

function startEscalationWatchdog({
  intervalMs = config.escalationTickMs,
  escalateAfterMs = config.escalateAfterMs
} = {}) {
  if (watchdogInterval) return;
  watchdogInterval = setInterval(() => {
    try {
      tickEscalation({ escalateAfterMs });
    } catch (err) {
      console.error('Watchdog escalation tick error:', err);
    }
  }, intervalMs);
  if (watchdogInterval && watchdogInterval.unref) {
    watchdogInterval.unref();
  }
}

function stopEscalationWatchdog() {
  if (watchdogInterval) {
    clearInterval(watchdogInterval);
    watchdogInterval = null;
  }
}

function isEscalationWatchdogRunning() {
  return watchdogInterval !== null;
}

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
      // The real Fast2SMS dispatch runs in the background after the alert is
      // persisted (see below) and updates this count via db.updateAlert.
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
  startEscalationWatchdog();

  // REAL_SMS_GATEWAY (Fast2SMS, DONE): background dispatch to the owner's
  // emergency contacts. The WS broadcast and HTTP response never wait on SMS
  // — an emergency must not be delayed by network latency. Dispatch failures
  // are logged and the honest delivered count is persisted + re-broadcast so
  // polling monitors see reality, never a fabricated number.
  if (userId) {
    const smsGateway = require('./smsGatewayService');
    if (smsGateway.isConfigured()) {
      const owner = db.findUserById(userId);
      smsGateway
        .dispatchSosNotifications({
          contacts: owner ? owner.emergencyContacts : null,
          userName: finalUserName,
          latitude: alert.latitude,
          longitude: alert.longitude,
          alertId: alert.id
        })
        .then(({ notified, total }) => {
          if (total === 0) return;
          db.updateAlert(alert.id, { emergencyContactsNotified: notified });
          console.log(`[smsGateway] SOS ${alert.id}: ${notified}/${total} emergency contacts notified`);
          const helpers = getBroadcastHelpers();
          const { toSafeAlert } = require('../models/alertModel');
          const fresh = db.findAlertById(alert.id);
          if (helpers.broadcastSosAlert && fresh) {
            helpers.broadcastSosAlert(toSafeAlert(fresh, false));
          }
        })
        .catch((err) => console.warn(`[smsGateway] SOS dispatch failed for ${alert.id}:`, err.message));
    }
  }
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

  const remainingActive = db.getActiveAlerts();
  if (remainingActive.length === 0) {
    stopEscalationWatchdog();
  }

  return updated;
}

// In-memory rate limiter for SOS chat: 1 msg per 2 seconds per sender
const chatRateLimits = new Map();

function checkChatRateLimit(key, now = Date.now()) {
  // Bound memory: opportunistically evict entries older than 1 hour once the
  // map grows large (keys are per-alert per-sender and never otherwise expire).
  if (chatRateLimits.size > 500) {
    for (const [k, t] of chatRateLimits) {
      if (now - t > 3600000) chatRateLimits.delete(k);
    }
  }
  const last = chatRateLimits.get(key) || 0;
  if (now - last < 2000) {
    return false;
  }
  chatRateLimits.set(key, now);
  return true;
}

function resetChatRateLimits() {
  chatRateLimits.clear();
}

function authenticateChatSender({ alert, user = null, token = null }) {
  if (!alert) return { authorized: false };

  // 1. Authenticated user object (from middleware)
  if (user) {
    if (user.role === 'admin' || user.role === 'responder' || user.role === 'first_responder') {
      return { authorized: true, role: 'responder', senderId: user.id };
    }
    if (alert.userId && alert.userId === user.id) {
      return { authorized: true, role: 'victim', senderId: user.id };
    }
  }

  // 2. Token (JWT access token or resolveToken)
  if (token) {
    try {
      const tokenService = require('./tokenService');
      const decoded = tokenService.verifyAccessToken(token);
      const uid = decoded && (decoded.sub || decoded.userId);
      if (uid) {
        const u = db.findUserById(uid);
        const role = (u && u.role) || decoded.role || 'citizen';
        if (role === 'admin' || role === 'responder' || role === 'first_responder') {
          return { authorized: true, role: 'responder', senderId: uid };
        }
        if (alert.userId && alert.userId === uid) {
          return { authorized: true, role: 'victim', senderId: uid };
        }
      }
    } catch (_) {}

    if (alert.resolveTokenHash) {
      const presentedHash = crypto.createHash('sha256').update(String(token)).digest('hex');
      const a = Buffer.from(presentedHash, 'utf8');
      const b = Buffer.from(String(alert.resolveTokenHash), 'utf8');
      if (a.length === b.length && crypto.timingSafeEqual(a, b)) {
        return { authorized: true, role: 'victim', senderId: alert.userId || 'anonymous' };
      }
    }
  }

  return { authorized: false };
}

module.exports = {
  triggerSos,
  getActiveAlerts,
  getAllAlerts,
  getAlertById,
  resolveSos,
  tickEscalation,
  startEscalationWatchdog,
  stopEscalationWatchdog,
  isEscalationWatchdogRunning,
  checkChatRateLimit,
  resetChatRateLimits,
  authenticateChatSender
};
