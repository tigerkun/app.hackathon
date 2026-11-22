/**
 * SOS Alert Routes
 * Express routes for /api/v1/sos/*
 */

const express = require('express');
const alertController = require('../controllers/alertController');
const { optionalAuth, requireAuth } = require('../middleware/authMiddleware');
const { validateSosTrigger } = require('../middleware/validation');
const { sosLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.post('/trigger', sosLimiter, optionalAuth, validateSosTrigger, alertController.trigger);
router.get('/active', optionalAuth, alertController.active);
router.get('/mine', requireAuth, alertController.mine);
router.get('/', optionalAuth, alertController.list);
router.post('/resolve', optionalAuth, alertController.resolve);
router.post('/:id/resolve', optionalAuth, alertController.resolve);
router.get('/:id/messages', optionalAuth, alertController.getMessages);
router.post('/:id/messages', sosLimiter, optionalAuth, alertController.postMessage);
router.get('/:id', optionalAuth, alertController.getById);

module.exports = router;
