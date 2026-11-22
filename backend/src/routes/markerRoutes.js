/**
 * Marker Routes
 * Express routes for /api/v1/markers/*
 */

const express = require('express');
const markerController = require('../controllers/markerController');
const { requireAuth, optionalAuth } = require('../middleware/authMiddleware');
const { markerLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.get('/', optionalAuth, markerController.list);
router.get('/nearby', optionalAuth, markerController.nearby);
router.get('/pending', requireAuth, markerController.pending);
router.post('/', optionalAuth, markerLimiter, markerController.create);
router.get('/:id', markerController.getById);
router.post('/:id/verify', requireAuth, markerController.verify);

module.exports = router;
