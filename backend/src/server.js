/**
 * SafeSphere Server Entry Point
 * Boots HTTP server and real-time WebSocket server for live SOS telemetry and broadcasts.
 */

const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const { app } = require('./app');
const config = require('./config');
const { db } = require('./data/store');

const server = http.createServer(app);

// WebSocket Server for Real-Time SOS Streaming
const wss = new WebSocketServer({ server, path: '/ws/sos', maxPayload: 16 * 1024 });

// Track connected WebSocket clients
const clients = new Set();

// Room-based session tracking for live guardian breadcrumbs: sessionId -> Set<ws>
const trackingRooms = new Map();

// Room-based alert tracking for live responder chat: alertId -> Set<ws>
const alertRooms = new Map();

wss.on('connection', (ws, req) => {
  clients.add(ws);
  ws.subscribedSessions = new Set();
  ws.subscribedAlerts = new Set();
  const ip = req.socket.remoteAddress;

  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.send(JSON.stringify({
    type: 'CONNECTION_ESTABLISHED',
    message: 'Connected to SafeSphere SOS WebSocket channel',
    timestamp: new Date().toISOString()
  }), (err) => {});

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());

      // NOTE: client-originated SOS_TELEMETRY / SOS_TRIGGER frames are NOT
      // relayed. Server-generated alerts are broadcast via broadcastSosAlert
      // from sosService; relaying unauthenticated client frames allowed any
      // connected socket to spoof emergency alerts to all monitors.
      if (message.type === 'SUBSCRIBE_TRACKING') {
        const sessionId = message.sessionId;
        if (!sessionId) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'MISSING_SESSION_ID',
            message: 'sessionId is required to subscribe to live tracking stream'
          }), (err) => {});
        }

        if (!verifyTrackingCredential(ws, sessionId, message.token)) {
          return;
        }

        if (!trackingRooms.has(sessionId)) {
          trackingRooms.set(sessionId, new Set());
        }
        trackingRooms.get(sessionId).add(ws);
        ws.subscribedSessions.add(sessionId);

        ws.send(JSON.stringify({
          type: 'SUBSCRIBED_TRACKING',
          sessionId,
          status: 'subscribed',
          timestamp: new Date().toISOString()
        }), (err) => {});

        // Send existing session snapshot if available in database
        try {
          const session = db.findTrackingSessionById(sessionId);
          if (session) {
            ws.send(JSON.stringify({
              type: 'TRACKING_SNAPSHOT',
              sessionId,
              session,
              timestamp: new Date().toISOString()
            }), (err) => {});
          }
        } catch (_) {}
      } else if (message.type === 'LOCATION_STREAM_UPDATE') {
        const { sessionId, latitude, longitude, speed, battery, accuracy, timestamp } = message;
        if (!sessionId || latitude === undefined || longitude === undefined) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'INVALID_STREAM_PAYLOAD',
            message: 'sessionId, latitude, and longitude are required for LOCATION_STREAM_UPDATE'
          }), (err) => {});
        }

        if (!verifyTrackingCredential(ws, sessionId, message.token)) {
          return;
        }

        // Persist breadcrumb in database — only broadcast if accepted.
        // Broadcasting rejected pings let guardians see "live" locations the
        // server refused to persist, and NaN coordinates could leak through.
        try {
          const trackingService = require('./services/trackingService');
          trackingService.recordPing({
            sessionId,
            latitude,
            longitude,
            speed,
            battery,
            accuracy,
            timestamp,
            token: message.token
          });
        } catch (err) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: err && err.code ? err.code : 'PING_REJECTED',
            message: (err && err.message) || 'Location ping rejected'
          }), (sendErr) => {});
        }

        // Broadcast to all subscribed guardians
        broadcastLocationUpdate(sessionId, {
          latitude,
          longitude,
          speed,
          battery,
          accuracy,
          timestamp
        }, ws);
      } else if (message.type === 'STREAM_TERMINATE') {
        const { sessionId, reason, token } = message;
        if (!sessionId) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'MISSING_SESSION_ID',
            message: 'sessionId is required to terminate a live tracking stream'
          }), (err) => {});
        }

        if (!verifyTrackingCredential(ws, sessionId, token)) {
          return;
        }

        try {
          const trackingService = require('./services/trackingService');
          trackingService.terminateTrackingSession(sessionId, reason, token);
        } catch (_) {}

        broadcastStreamTerminate(sessionId, reason, ws);
      } else if (message.type === 'SUBSCRIBE_ALERT') {
        const alertId = message.alertId;
        if (!alertId) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'MISSING_ALERT_ID',
            message: 'alertId is required to subscribe to alert room'
          }), (err) => {});
        }

        // Alert rooms carry responder chat — subscribing requires the same
        // credential as sending (JWT, responder role, or valid resolveToken).
        const alert = db.findAlertById(alertId);
        if (!alert) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'ALERT_NOT_FOUND',
            message: `Alert ${alertId} not found`
          }), (err) => {});
        }
        const subscribeToken = message.token || message.sessionId || message.resolveToken;
        const sosService = require('./services/sosService');
        const authResult = sosService.authenticateChatSender({ alert, token: subscribeToken });
        if (!authResult.authorized) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'UNAUTHORIZED_ALERT_SUBSCRIBE',
            message: 'Valid credentials are required to subscribe to this alert room'
          }), (err) => {});
        }

        if (!alertRooms.has(alertId)) {
          alertRooms.set(alertId, new Set());
        }
        alertRooms.get(alertId).add(ws);
        ws.subscribedAlerts.add(alertId);

        ws.send(JSON.stringify({
          type: 'SUBSCRIBED_ALERT',
          alertId,
          status: 'subscribed',
          timestamp: new Date().toISOString()
        }), (err) => {});
      } else if (message.type === 'CHAT_MESSAGE') {
        const { alertId, text } = message;
        const token = message.token || message.sessionId || message.resolveToken;
        if (!alertId) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'MISSING_ALERT_ID',
            message: 'alertId is required for CHAT_MESSAGE'
          }), (err) => {});
        }
        if (typeof text !== 'string' || text.trim().length === 0 || text.trim().length > 500) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'INVALID_CHAT_TEXT',
            message: 'Chat text must be between 1 and 500 characters'
          }), (err) => {});
        }
        const alert = db.findAlertById(alertId);
        if (!alert) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'ALERT_NOT_FOUND',
            message: `Alert ${alertId} not found`
          }), (err) => {});
        }
        const sosService = require('./services/sosService');
        const authResult = sosService.authenticateChatSender({ alert, token });
        if (!authResult.authorized) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'UNAUTHORIZED_CHAT',
            message: 'Authentication or valid resolveToken is required to send chat messages'
          }), (err) => {});
        }
        const rateKey = `${alertId}:${authResult.senderId || authResult.role}`;
        if (!sosService.checkChatRateLimit(rateKey)) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'RATE_LIMIT_EXCEEDED',
            message: 'Rate limit: max 1 message per 2 seconds'
          }), (err) => {});
        }
        // Auto-join room for sender
        if (!alertRooms.has(alertId)) {
          alertRooms.set(alertId, new Set());
        }
        alertRooms.get(alertId).add(ws);
        ws.subscribedAlerts.add(alertId);

        const saved = db.saveSosMessage({
          alertId,
          senderRole: authResult.role,
          senderId: authResult.senderId,
          text: text.trim(),
          createdAt: new Date().toISOString()
        });
        broadcastSosChatMessage({ alertId, message: saved });
      } else if (message.type === 'PING') {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }), (err) => {});
      }
    } catch (e) {
      ws.send(JSON.stringify({ type: 'ERROR', message: 'Malformed JSON payload' }), (err) => {});
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    if (ws.subscribedSessions) {
      for (const sId of ws.subscribedSessions) {
        const room = trackingRooms.get(sId);
        if (room) {
          room.delete(ws);
          if (room.size === 0) {
            trackingRooms.delete(sId);
          }
        }
      }
    }
    if (ws.subscribedAlerts) {
      for (const aId of ws.subscribedAlerts) {
        const room = alertRooms.get(aId);
        if (room) {
          room.delete(ws);
          if (room.size === 0) {
            alertRooms.delete(aId);
          }
        }
      }
    }
  });

  ws.on('error', () => {
    clients.delete(ws);
    if (ws.subscribedSessions) {
      for (const sId of ws.subscribedSessions) {
        const room = trackingRooms.get(sId);
        if (room) {
          room.delete(ws);
          if (room.size === 0) {
            trackingRooms.delete(sId);
          }
        }
      }
    }
    if (ws.subscribedAlerts) {
      for (const aId of ws.subscribedAlerts) {
        const room = alertRooms.get(aId);
        if (room) {
          room.delete(ws);
          if (room.size === 0) {
            alertRooms.delete(aId);
          }
        }
      }
    }
  });
});

// Periodic ping heartbeat to prune dead sockets
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      clients.delete(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);
if (pingInterval.unref) {
  pingInterval.unref();
}

// Periodic 60s watchdog to evaluate tracking check-in deadlines
const checkInWatchdogInterval = setInterval(() => {

  try {
    const trackingService = require('./services/trackingService');
    trackingService.processCheckInDeadlines(new Date());
  } catch (err) {
    console.error('Check-in watchdog tick error:', err);
  }
}, 60000);
if (checkInWatchdogInterval.unref) {
  checkInWatchdogInterval.unref();
}

// Start the SOS escalation watchdog at boot — persisted active alerts must
// keep escalating across restarts, not only after the next triggerSos call.
try {
  require('./services/sosService').startEscalationWatchdog();
} catch (err) {
  console.error('Failed to start SOS escalation watchdog:', err);
}

wss.on('close', () => {
  clearInterval(pingInterval);
  clearInterval(checkInWatchdogInterval);
  try {
    const { stopEscalationWatchdog } = require('./services/sosService');
    stopEscalationWatchdog();
  } catch (_) {}
});

/**
 * Validate a tracking session credential for WebSocket tracking operations.
 * The session token IS the credential (guest/anonymous sessions included).
 * Sends an ERROR frame and returns false when the token is missing or invalid.
 */
function verifyTrackingCredential(ws, sessionId, token) {
  if (token === undefined || token === null || token === '') {
    ws.send(JSON.stringify({
      type: 'ERROR',
      code: 'MISSING_TRACKING_TOKEN',
      message: 'token is required to access this live tracking stream'
    }), (err) => {});
    return false;
  }

  let trackingService;
  try {
    trackingService = require('./services/trackingService');
  } catch (_) {
    trackingService = null;
  }

  if (!trackingService || !trackingService.isValidTrackingToken(sessionId, token)) {
    ws.send(JSON.stringify({
      type: 'ERROR',
      code: 'INVALID_TRACKING_TOKEN',
      message: 'Invalid tracking token for this live tracking session'
    }), (err) => {});
    return false;
  }

  return true;
}

// Broadcast helper for external invocation
function broadcastSosAlert(alertData) {
  const payload = JSON.stringify({
    type: 'SOS_ALERT_BROADCAST',
    data: alertData,
    timestamp: new Date().toISOString()
  });

  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
    }
  }
}

// Broadcast escalation event to all connected monitors
function broadcastSosEscalated({ alertId, level, elapsedMin }) {
  const payload = JSON.stringify({
    type: 'SOS_ESCALATED',
    alertId,
    level: Number(level),
    elapsedMin: Number(elapsedMin),
    timestamp: new Date().toISOString()
  });

  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
    }
  }
}

// Broadcast SOS chat message to alert room subscribers and connected monitors
function broadcastSosChatMessage({ alertId, message }) {
  const { toSafeSosMessage } = require('./models/sosMessageModel');
  const safeMessage = toSafeSosMessage(message);
  const room = alertRooms.get(alertId);
  if (!room || room.size === 0) return;
  const payload = JSON.stringify({
    type: 'CHAT_MESSAGE',
    alertId,
    message: safeMessage,
    timestamp: safeMessage.createdAt || new Date().toISOString()
  });

  // Chat is credential-gated: deliver ONLY to authenticated room members.
  // Broadcasting to every unscoped client leaked private responder/victim
  // messages to anyone connected to /ws/sos.
  for (const client of room) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
    }
  }
}

// Broadcast location stream update to all guardians subscribed to a session
function broadcastLocationUpdate(sessionId, locationData, senderWs = null) {
  const room = trackingRooms.get(sessionId);
  if (!room || room.size === 0) return 0;

  const payload = JSON.stringify({
    type: 'LOCATION_STREAM_UPDATE',
    sessionId,
    latitude: Number(locationData.latitude),
    longitude: Number(locationData.longitude),
    speed: locationData.speed !== undefined && locationData.speed !== null ? Number(locationData.speed) : 0,
    battery: locationData.battery !== undefined && locationData.battery !== null ? Number(locationData.battery) : null,
    accuracy: locationData.accuracy !== undefined && locationData.accuracy !== null ? Number(locationData.accuracy) : null,
    timestamp: locationData.timestamp || new Date().toISOString(),
    relayedAt: new Date().toISOString()
  });

  let sentCount = 0;
  for (const client of room) {
    if (client !== senderWs && client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
      sentCount++;
    }
  }
  return sentCount;
}

// Broadcast session stream termination to all guardians subscribed to a session
function broadcastStreamTerminate(sessionId, reason = 'Stream terminated by user', senderWs = null) {
  const room = trackingRooms.get(sessionId);
  if (!room || room.size === 0) return 0;

  const payload = JSON.stringify({
    type: 'STREAM_TERMINATE',
    sessionId,
    reason: String(reason || 'Stream terminated by user'),
    relayedAt: new Date().toISOString()
  });

  let sentCount = 0;
  for (const client of room) {
    if (client !== senderWs && client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
      sentCount++;
    }
  }
  return sentCount;
}

// Broadcast missed check-in event to all guardians subscribed to a session
function broadcastCheckInMissed({ sessionId, missedCheckIns, checkInDeadline, timestamp }) {
  const room = trackingRooms.get(sessionId);
  if (!room || room.size === 0) return 0;

  const payload = JSON.stringify({
    type: 'CHECKIN_MISSED',
    sessionId,
    missedCheckIns: Number(missedCheckIns),
    checkInDeadline: checkInDeadline || null,
    timestamp: timestamp || new Date().toISOString()
  });

  let sentCount = 0;
  for (const client of room) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload, (err) => {});
      sentCount++;
    }
  }
  return sentCount;
}

/**
 * Returns the count of actively connected WebSocket clients.
 */
function getWebSocketClientCount() {
  return clients.size;
}

/**
 * Gracefully shuts down the HTTP and WebSocket servers and closes the SQLite database connection.
 * @param {Function} [callback] Optional callback invoked upon clean termination instead of process.exit.
 */
const shutdown = (callback) => {
  console.log('\nGracefully shutting down SafeSphere server...');
  clearInterval(pingInterval);
  clearInterval(checkInWatchdogInterval);

  try {
    const { stopEscalationWatchdog } = require('./services/sosService');
    stopEscalationWatchdog();
  } catch (_) {}

  for (const client of clients) {
    try {
      client.terminate();
    } catch (_) {}
  }
  clients.clear();

  wss.close(() => {
    server.close(async () => {
      try {
        // Flush the final durable snapshot BEFORE closing the SQLite handle
        // (best-effort, capped at 5s so shutdown never hangs).
        const { persistSnapshotNow } = require('./data/dbSnapshot');
        await Promise.race([
          persistSnapshotNow(() => db),
          new Promise((resolve) => setTimeout(resolve, 5000))
        ]);
      } catch (_) {}
      try {
        if (db && typeof db.close === 'function') {
          db.close();
        }
      } catch (err) {
        console.error('Error closing database handle:', err.message);
      }
      console.log('SafeSphere server terminated cleanly.');
      if (typeof callback === 'function') {
        callback();
      } else {
        process.exit(0);
      }
    });
  });
};

// Start Server if run directly — after hydrating the DB from the durable
// remote snapshot (Supabase Storage) so no request ever sees a half-booted store.
if (require.main === module) {
  (async () => {
    const { hydrateStoreFromSnapshot, startSnapshotPersistence } = require('./data/dbSnapshot');
    await hydrateStoreFromSnapshot(() => db);
    startSnapshotPersistence(() => db);

    server.listen(config.port, '0.0.0.0', () => {
      console.log(`========================================================`);
      console.log(`  SafeSphere Backend Service`);
      console.log(`  Environment: ${config.nodeEnv}`);
      console.log(`  HTTP API:    http://127.0.0.1:${config.port}`);
      console.log(`  WebSocket:   ws://127.0.0.1:${config.port}/ws/sos`);
      console.log(`========================================================`);
    });

    process.on('SIGINT', () => shutdown());
    process.on('SIGTERM', () => shutdown());
  })().catch((err) => {
    console.error('Fatal boot failure:', err.message);
    process.exit(1);
  });
}

module.exports = {
  server,
  wss,
  clients,
  getWebSocketClientCount,
  shutdown,
  broadcastSosAlert,
  broadcastSosEscalated,
  broadcastSosChatMessage,
  broadcastLocationUpdate,
  broadcastStreamTerminate,
  broadcastCheckInMissed,
  trackingRooms,
  alertRooms
};
