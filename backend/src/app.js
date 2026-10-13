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

// Root System Health Check (for Docker, load balancers, and monitoring)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'safesphere-backend',
    version: '1.0.0',
    uptimeSeconds: Math.floor(process.uptime())
  });
});

app.get('/', (req, res) => {
  res.status(200).json({
    name: 'SafeSphere API Service',
    status: 'operational',
    version: '1.0.0',
    apiRoot: '/api/v1'
  });
});

// API Version 1
app.use('/api/v1', apiV1Router);

// Centralized Error Handling
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = {
  app
};
