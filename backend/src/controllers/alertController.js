/**
 * Alert Controller
 * Handles real-time emergency SOS trigger, active alert broadcast, and resolution.
 */

const sosService = require('../services/sosService');
const { db } = require('../data/store');
const { toSafeAlert } = require('../models/alertModel');
const { toSafeSosMessage } = require('../models/sosMessageModel');
const crypto = require('crypto');

// Attach indexed getAlertsByUserId to DataStore if not present
if (typeof db.getAlertsByUserId !== 'function') {
  db.constructor.prototype.getAlertsByUserId = function(userId, status = null) {
    if (!userId) return [];
    let sql = 'SELECT * FROM alerts WHERE userId = ?';
    const params = [userId];
    if (status) {
      sql += ' AND LOWER(status) = ?';
      params.push(String(status).toLowerCase());
    }
    sql += ' ORDER BY triggeredAt DESC';
    const rows = this.db.prepare(sql).all(...params);
    return rows.map((r) => this._formatAlert(r));
  };
}

function verifyResolveToken(alert, presentedToken) {
  if (!presentedToken || !alert.resolveTokenHash) return false;
  const presentedHash = crypto.createHash('sha256').update(String(presentedToken)).digest('hex');
  const a = Buffer.from(presentedHash, 'utf8');
  const b = Buffer.from(String(alert.resolveTokenHash), 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Lazy-reference broadcastSosAlert to avoid circular dependency issues at boot
function getBroadcastHelper() {
  try {
    const serverModule = require('../server');
    return serverModule.broadcastSosAlert;
  } catch (_) {
    return null;
  }
}

function getWebSocketMonitorCount() {
  try {
    const serverModule = require('../server');
    if (typeof serverModule.getWebSocketClientCount === 'function') {
      return serverModule.getWebSocketClientCount();
    } else if (serverModule.wss && serverModule.wss.clients) {
      return serverModule.wss.clients.size;
    }
  } catch (_) {}
  return 0;
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

    const responseAlert = { ...alert };
    delete responseAlert.resolveTokenHash;

    res.status(201).json({
      success: true,
      message: 'Emergency SOS alert triggered successfully',
      data: responseAlert,
      ...responseAlert
    });
  } catch (err) {
    next(err);
  }
}

function active(req, res, next) {
  try {
    const rawAlerts = sosService.getActiveAlerts();
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));
    const limit = Math.min(Math.max(1, parseInt(req.query.limit, 10) || 50), 100);
    const alerts = rawAlerts.slice(0, limit).map(a => {
      const isOwner = req.user && req.user.id === a.userId;
      return toSafeAlert(a, isOwner || isPrivileged);
    });

    const monitorsConnected = getWebSocketMonitorCount();

    res.status(200).json({
      success: true,
      count: alerts.length,
      monitorsConnected,
      data: alerts
    });
  } catch (err) {
    next(err);
  }
}

function mine(req, res, next) {
  try {
    const userId = req.user.id;
    const limit = Math.min(Math.max(1, parseInt(req.query.limit, 10) || 50), 100);
    const statusFilter = req.query.status ? String(req.query.status).toLowerCase() : null;
    const rawAlerts = db.getAlertsByUserId(userId, statusFilter);
    const myAlerts = rawAlerts
      .slice(0, limit)
      .map(a => toSafeAlert(a, true));

    res.status(200).json({
      success: true,
      count: myAlerts.length,
      data: myAlerts
    });
  } catch (err) {
    next(err);
  }
}

function list(req, res, next) {
  try {
    const rawAlerts = sosService.getAllAlerts();
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));
    const limit = Math.min(Math.max(1, parseInt(req.query.limit, 10) || 50), 100);
    const alerts = rawAlerts.slice(0, limit).map(a => {
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

    const monitorsConnected = getWebSocketMonitorCount();
    const safeData = toSafeAlert(alert, isOwner || isPrivileged);

    res.status(200).json({
      success: true,
      monitorsConnected,
      data: {
        ...safeData,
        monitorsConnected
      }
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
    const isAnonymousAlert = !existing.userId || existing.userId === 'anonymous';
    const isPrivileged = !!(req.user && (req.user.role === 'admin' || req.user.role === 'first_responder'));

    if (isAnonymousAlert) {
      // Anonymous alerts: admin/first_responder OR possession of the per-alert
      // resolveToken issued at trigger time (the victim's "I'm Safe Now"
      // credential). Guests have no account, so the token is the only path.
      const presentedToken = req.body && (req.body.resolveToken || req.body.resolve_token || req.body.token);
      if (!isPrivileged && !verifyResolveToken(existing, presentedToken)) {
        return res.status(req.user ? 403 : 401).json({
          success: false,
          error: {
            code: req.user ? 'FORBIDDEN_RESOLVE' : 'UNAUTHORIZED_RESOLVE',
            message: req.user
              ? 'Only responders, administrators, or the alert resolve token may resolve anonymous SOS alerts'
              : 'Authentication or a valid resolve token is required to resolve this SOS alert',
            details: []
          }
        });
      }
    } else {
      // Owned alerts require authentication.
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
      if (!isOwner && !isPrivileged) {
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
    const safeUpdated = toSafeAlert(updated, true);

    res.status(200).json({
      success: true,
      message: 'Emergency SOS alert resolved successfully',
      data: safeUpdated
    });
  } catch (err) {
    next(err);
  }
}

function getChatBroadcastHelper() {
  try {
    const serverModule = require('../server');
    return serverModule.broadcastSosChatMessage;
  } catch (_) {
    return null;
  }
}

function postMessage(req, res, next) {
  try {
    const alertId = req.params.id;
    const body = req.body || {};
    const text = body.text;
    const bearerToken = req.headers.authorization && req.headers.authorization.startsWith('Bearer ')
      ? req.headers.authorization.slice(7).trim()
      : null;
    const token = body.token || body.resolveToken || req.query.token || bearerToken;

    if (!alertId) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_ALERT_ID',
          message: 'Alert ID is required to post messages',
          details: []
        }
      });
    }

    if (typeof text !== 'string' || text.trim().length === 0 || text.trim().length > 500) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'INVALID_CHAT_TEXT',
          message: 'Message text must be between 1 and 500 characters',
          details: []
        }
      });
    }

    const alert = db.findAlertById(alertId);
    if (!alert) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'ALERT_NOT_FOUND',
          message: `SOS alert ${alertId} not found`,
          details: []
        }
      });
    }

    const authResult = sosService.authenticateChatSender({ alert, user: req.user, token });
    if (!authResult.authorized) {
      return res.status(req.user ? 403 : 401).json({
        success: false,
        error: {
          code: req.user ? 'FORBIDDEN_CHAT' : 'UNAUTHORIZED_CHAT',
          message: 'Authentication or a valid resolveToken is required to participate in SOS chat',
          details: []
        }
      });
    }

    const senderKey = `${alertId}:${authResult.senderId || authResult.role}`;
    if (!sosService.checkChatRateLimit(senderKey)) {
      return res.status(429).json({
        success: false,
        error: {
          code: 'RATE_LIMIT_EXCEEDED',
          message: 'Rate limit: max 1 message per 2 seconds',
          details: []
        }
      });
    }

    const saved = db.saveSosMessage({
      alertId,
      senderRole: authResult.role,
      senderId: authResult.senderId,
      text: text.trim(),
      createdAt: new Date().toISOString()
    });

    const safeMessage = toSafeSosMessage(saved);

    const broadcast = getChatBroadcastHelper();
    if (typeof broadcast === 'function') {
      broadcast({ alertId, message: safeMessage });
    }

    res.status(201).json({
      success: true,
      message: 'SOS chat message posted successfully',
      data: safeMessage
    });
  } catch (err) {
    next(err);
  }
}

function getMessages(req, res, next) {
  try {
    const alertId = req.params.id;
    const bearerToken = req.headers.authorization && req.headers.authorization.startsWith('Bearer ')
      ? req.headers.authorization.slice(7).trim()
      : null;
    const token = req.query.token || (req.body && (req.body.token || req.body.resolveToken)) || bearerToken;

    if (!alertId) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_ALERT_ID',
          message: 'Alert ID is required to fetch messages',
          details: []
        }
      });
    }

    const alert = db.findAlertById(alertId);
    if (!alert) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'ALERT_NOT_FOUND',
          message: `SOS alert ${alertId} not found`,
          details: []
        }
      });
    }

    const authResult = sosService.authenticateChatSender({ alert, user: req.user, token });
    if (!authResult.authorized) {
      return res.status(req.user ? 403 : 401).json({
        success: false,
        error: {
          code: req.user ? 'FORBIDDEN_CHAT' : 'UNAUTHORIZED_CHAT',
          message: 'Authentication or a valid resolveToken is required to read SOS chat messages',
          details: []
        }
      });
    }

    const limit = Math.min(Math.max(1, parseInt(req.query.limit, 10) || 50), 50);
    const messages = db.getSosMessages(alertId, limit);

    res.status(200).json({
      success: true,
      count: messages.length,
      data: messages.map(m => toSafeSosMessage(m))
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  trigger,
  active,
  list,
  mine,
  getById,
  resolve,
  postMessage,
  getMessages
};
