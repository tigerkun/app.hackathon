/**
 * SafeSphere Express Application
 * Configures middleware, security, route aggregators, and centralized error handling.
 */

const express = require('express');
const cors = require('cors');
const config = require('./config');
const apiV1Router = require('./routes');
const { globalLimiter } = require('./middleware/rateLimiter');
const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');

const app = express();

// Security & Parsing Middleware
app.use(cors({
  origin: config.corsOrigin,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Global sliding window rate limiter
app.use(globalLimiter);

const { trackerHtml } = require('./views/trackerPage');

// Root System Health Check (for Docker, load balancers, and monitoring)
app.get('/health', (req, res) => {
  const start = Date.now();
  let dbStatus = 'OK';
  let dbReachable = true;

  try {
    const { db } = require('./data/store');
    if (!db || !db.db) {
      dbStatus = 'DOWN';
      dbReachable = false;
    } else {
      const row = db.db.prepare('SELECT 1 AS ok').get();
      if (!row || row.ok !== 1) {
        dbStatus = 'ERROR';
        dbReachable = false;
      }
    }
  } catch (err) {
    dbStatus = 'ERROR';
    dbReachable = false;
  }

  let wsClients = 0;
  try {
    const serverModule = require('./server');
    if (typeof serverModule.getWebSocketClientCount === 'function') {
      wsClients = serverModule.getWebSocketClientCount();
    } else if (serverModule.wss && serverModule.wss.clients) {
      wsClients = serverModule.wss.clients.size;
    }
  } catch (_) {
    wsClients = 0;
  }

  const uptime = process.uptime();
  const isHealthy = dbReachable;

  res.status(isHealthy ? 200 : 503).json({
    status: isHealthy ? 'healthy' : 'unhealthy',
    timestamp: new Date().toISOString(),
    service: 'safesphere-backend',
    version: '1.0.0',
    uptime,
    uptimeSeconds: Math.floor(uptime),
    database: dbStatus,
    databaseStatus: dbStatus,
    db: dbStatus.toLowerCase(),
    wsClients,
    wsClientCount: wsClients,
    isProduction: config.isProduction,
    demoMode: config.isDemoMode,
    responseTimeMs: Date.now() - start
  });
});

// Lightweight Liveness Endpoint (Docker / K8s liveness probe)
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Root API Metadata or Browser-accessible Guardian Tracker (W2-1)
app.get('/', (req, res) => {
  if (req.query.session || req.query.token) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.status(200).send(trackerHtml);
  }
  res.status(200).json({
    name: 'SafeSphere API Service',
    status: 'operational',
    version: '1.0.0',
    apiRoot: '/api/v1'
  });
});

// Dedicated /track browser route
app.get('/track', (req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  return res.status(200).send(trackerHtml);
});

// API Version 1
app.use('/api/v1', apiV1Router);

// Centralized Error Handling
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = {
  app
};
