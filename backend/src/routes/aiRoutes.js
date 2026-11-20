/**
 * AI Assistant Routes
 * Express routes for /api/v1/ai/*
 */

const express = require('express');
const aiController = require('../controllers/aiController');
const { optionalAuth } = require('../middleware/authMiddleware');
const { aiLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.post('/chat', aiLimiter, optionalAuth, aiController.chat);

module.exports = router;
