/**
 * API v1 Aggregate Router
 * Mounts all modular domain routers under /api/v1.
 */

const express = require('express');
const authRoutes = require('./authRoutes');
const reportRoutes = require('./reportRoutes');
const markerRoutes = require('./markerRoutes');
const alertRoutes = require('./alertRoutes');

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
      sos: '/api/v1/sos'
    }
  });
});

// Domain route modules
router.use('/auth', authRoutes);
router.use('/reports', reportRoutes);
router.use('/markers', markerRoutes);
router.use('/sos', alertRoutes);

module.exports = router;
