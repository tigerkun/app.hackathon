/**
 * API v1 Aggregate Router
 * Mounts all modular domain routers under /api/v1.
 */

const express = require('express');
const authRoutes = require('./authRoutes');
const reportRoutes = require('./reportRoutes');
const markerRoutes = require('./markerRoutes');
const alertRoutes = require('./alertRoutes');
const locationRoutes = require('./locationRoutes');
const aiRoutes = require('./aiRoutes');
const connectionRoutes = require('./connectionRoutes');

const router = express.Router();

// Root API v1 info
router.get('/', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'SafeSphere REST API',
    version: 'v1',
    endpoints: {
      auth: '/api/v1/auth',
      reports: '/api/v1/reports',
      markers: '/api/v1/markers',
      sos: '/api/v1/sos',
      location: '/api/v1/location',
      ai: '/api/v1/ai',
      connections: '/api/v1/connections'
    }
  });
});

// Domain route modules
router.use('/auth', authRoutes);
router.use('/reports', reportRoutes);
router.use('/markers', markerRoutes);
router.use('/sos', alertRoutes);
router.use('/location', locationRoutes);
router.use('/ai', aiRoutes);
router.use('/connections', connectionRoutes);

module.exports = router;
