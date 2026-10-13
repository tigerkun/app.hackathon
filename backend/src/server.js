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

wss.on('connection', (ws, req) => {
  clients.add(ws);
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
      } else if (message.type === 'PING') {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }));
      }
    } catch (e) {
      ws.send(JSON.stringify({ type: 'ERROR', message: 'Malformed JSON payload' }));
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
  });

  ws.on('error', () => {
    clients.delete(ws);
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
  broadcastSosAlert
};
