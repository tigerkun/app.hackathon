/**
 * Report Routes
 * Express routes for /api/v1/reports/*
 */

const express = require('express');
const reportController = require('../controllers/reportController');
const { optionalAuth } = require('../middleware/authMiddleware');
const { validateReportCreate } = require('../middleware/validation');

const router = express.Router();

router.get('/', reportController.list);
router.post('/', optionalAuth, validateReportCreate, reportController.create);
router.get('/:id', reportController.getById);

module.exports = router;
