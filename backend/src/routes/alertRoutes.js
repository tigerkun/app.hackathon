/**
 * SOS Alert Routes
 * Express routes for /api/v1/sos/*
 */

const express = require('express');
const alertController = require('../controllers/alertController');
const { optionalAuth } = require('../middleware/authMiddleware');
const { validateSosTrigger } = require('../middleware/validation');

const router = express.Router();

router.post('/trigger', optionalAuth, validateSosTrigger, alertController.trigger);
router.get('/active', alertController.active);
router.get('/', alertController.list);
router.post('/resolve', alertController.resolve);
router.post('/:id/resolve', alertController.resolve);
router.get('/:id', alertController.getById);

module.exports = router;
