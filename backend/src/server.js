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
const wss = new WebSocketServer({ server, path: '/ws/sos' });

// Track connected WebSocket clients
const clients = new Set();

// Room-based session tracking for live guardian breadcrumbs: sessionId -> Set<ws>
const trackingRooms = new Map();

wss.on('connection', (ws, req) => {
  clients.add(ws);
  ws.subscribedSessions = new Set();
  const ip = req.socket.remoteAddress;

  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.send(JSON.stringify({
    type: 'CONNECTION_ESTABLISHED',
    message: 'Connected to SafeSphere SOS WebSocket channel',
    timestamp: new Date().toISOString()
  }));

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());

      // Broadcast emergency telemetry to all active monitors/dispatchers
      if (message.type === 'SOS_TELEMETRY' || message.type === 'SOS_TRIGGER') {
        const payload = JSON.stringify({
          ...message,
          relayedAt: new Date().toISOString()
        });

        for (const client of clients) {
          if (client !== ws && client.readyState === WebSocket.OPEN) {
            client.send(payload);
          }
        }
      } else if (message.type === 'SUBSCRIBE_TRACKING') {
        const sessionId = message.sessionId;
        if (!sessionId) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'MISSING_SESSION_ID',
            message: 'sessionId is required to subscribe to live tracking stream'
          }));
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
        }));

        // Send existing session snapshot if available in database
        try {
          const session = db.findTrackingSessionById(sessionId);
          if (session) {
            ws.send(JSON.stringify({
              type: 'TRACKING_SNAPSHOT',
              sessionId,
              session,
              timestamp: new Date().toISOString()
            }));
          }
        } catch (_) {}
      } else if (message.type === 'LOCATION_STREAM_UPDATE') {
        const { sessionId, latitude, longitude, speed, battery, accuracy, timestamp } = message;
        if (!sessionId || latitude === undefined || longitude === undefined) {
          return ws.send(JSON.stringify({
            type: 'ERROR',
            code: 'INVALID_STREAM_PAYLOAD',
            message: 'sessionId, latitude, and longitude are required for LOCATION_STREAM_UPDATE'
          }));
        }

        // Persist breadcrumb in database
        try {
          const trackingService = require('./services/trackingService');
          trackingService.recordPing({
            sessionId,
            latitude,
            longitude,
            speed,
            battery,
            accuracy,
            timestamp
          });
        } catch (_) {}

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
        const { sessionId, reason } = message;
        if (sessionId) {
          try {
            const trackingService = require('./services/trackingService');
            trackingService.terminateTrackingSession(sessionId, reason);
          } catch (_) {}

          broadcastStreamTerminate(sessionId, reason, ws);
        }
      } else if (message.type === 'PING') {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }));
      }
    } catch (e) {
      ws.send(JSON.stringify({ type: 'ERROR', message: 'Malformed JSON payload' }));
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

wss.on('close', () => {
  clearInterval(pingInterval);
});

// Broadcast helper for external invocation
function broadcastSosAlert(alertData) {
  const payload = JSON.stringify({
    type: 'SOS_ALERT_BROADCAST',
    data: alertData,
    timestamp: new Date().toISOString()
  });

  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
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
      client.send(payload);
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
      client.send(payload);
      sentCount++;
    }
  }
  return sentCount;
}

// Start Server if run directly
if (require.main === module) {
  server.listen(config.port, '0.0.0.0', () => {
    console.log(`========================================================`);
    console.log(`  SafeSphere Backend Service`);
    console.log(`  Environment: ${config.nodeEnv}`);
    console.log(`  HTTP API:    http://127.0.0.1:${config.port}`);
    console.log(`  WebSocket:   ws://127.0.0.1:${config.port}/ws/sos`);
    console.log(`========================================================`);
  });

  const shutdown = () => {
    console.log('\nGracefully shutting down SafeSphere server...');
    clearInterval(pingInterval);
    wss.close(() => {
      server.close(() => {
        console.log('SafeSphere server terminated cleanly.');
        process.exit(0);
      });
    });
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

module.exports = {
  server,
  wss,
  broadcastSosAlert,
  broadcastLocationUpdate,
  broadcastStreamTerminate,
  trackingRooms
};
