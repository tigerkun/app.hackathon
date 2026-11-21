/**
 * Report Routes
 * Express routes for /api/v1/reports/*
 */

const express = require('express');
const reportController = require('../controllers/reportController');
const { requireAuth, optionalAuth, rejectBanned } = require('../middleware/authMiddleware');
const { validateReportCreate } = require('../middleware/validation');
const { reportLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.get('/', optionalAuth, reportController.list);
router.post('/', requireAuth, rejectBanned, reportLimiter, validateReportCreate, reportController.create);
router.post('/:id/vote', requireAuth, rejectBanned, reportController.vote);
router.get('/:id', optionalAuth, reportController.getById);
router.post('/:id/status', requireAuth, reportController.updateStatus);

module.exports = router;
