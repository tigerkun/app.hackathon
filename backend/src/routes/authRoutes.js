/**
 * Auth Routes
 * Express routes for /api/v1/auth/*
 */

const express = require('express');
const authController = require('../controllers/authController');
const { requireAuth } = require('../middleware/authMiddleware');
const { authLimiter } = require('../middleware/rateLimiter');
const {
  validateRegister,
  validateLogin,
  validateLoginPin,
  validateOtpSend,
  validateOtpVerify,
  validateRefresh
} = require('../middleware/validation');

const router = express.Router();

// Registration (supports both /register and legacy /signup)
router.post('/register', authLimiter, validateRegister, authController.register);
router.post('/signup', authLimiter, validateRegister, authController.register);

// Authentication
router.post('/login', authLimiter, validateLogin, authController.login);
router.post('/login-pin', authLimiter, validateLoginPin, authController.loginPin);

// OTP SMS flow
router.post('/otp/send', validateOtpSend, authController.sendOtp);
router.post('/otp/verify', validateOtpVerify, authController.verifyOtp);

// Session token refresh
router.post('/refresh', validateRefresh, authController.refresh);

// Protected user profile
router.get('/me', requireAuth, authController.me);

// Session logout
router.post('/logout', requireAuth, authController.logout);

// Biometrics multi-modal
router.post('/biometrics/register', requireAuth, authController.registerBiometrics);
router.post('/biometrics/login', authLimiter, authController.loginBiometrics);

module.exports = router;
