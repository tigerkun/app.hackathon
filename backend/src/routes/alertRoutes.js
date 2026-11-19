/**
 * SOS Alert Routes
 * Express routes for /api/v1/sos/*
 */

const express = require('express');
const alertController = require('../controllers/alertController');
const { optionalAuth, requireAuth } = require('../middleware/authMiddleware');
const { validateSosTrigger } = require('../middleware/validation');

const router = express.Router();

router.post('/trigger', optionalAuth, validateSosTrigger, alertController.trigger);
router.get('/active', optionalAuth, alertController.active);
router.get('/mine', requireAuth, alertController.mine);
router.get('/', optionalAuth, alertController.list);
router.post('/resolve', optionalAuth, alertController.resolve);
router.post('/:id/resolve', optionalAuth, alertController.resolve);
router.get('/:id', optionalAuth, alertController.getById);

module.exports = router;
