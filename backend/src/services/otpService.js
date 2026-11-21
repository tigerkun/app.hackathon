/**
 * OTP Service
 * Handles cryptographic 6-digit random OTP generation, 60s cooldown throttling,
 * 3-attempt lockout security, and development bypass support.
 */

const crypto = require('crypto');
const config = require('../config');
const { db } = require('../data/store');
const { normalizePhone } = require('../models/userModel');

function generateOtpCode() {
  return String(crypto.randomInt(100000, 1000000));
}

async function sendOtp(rawPhone, purpose = 'login') {
  const phone = normalizePhone(rawPhone);
  if (!phone) {
    const error = new Error('Valid phone number is required');
    error.status = 400;
    error.code = 'INVALID_PHONE';
    throw error;
  }

  const existing = db.getOtp(phone);
  const now = Date.now();

  // Check Cooldown (60 seconds)
  if (existing && now < existing.cooldownUntil) {
    const remainingSeconds = Math.ceil((existing.cooldownUntil - now) / 1000);
    const error = new Error(`Please wait ${remainingSeconds} seconds before requesting another code.`);
    error.status = 429;
    error.code = 'OTP_COOLDOWN_ACTIVE';
    error.retryAfter = remainingSeconds;
    throw error;
  }

  const code = generateOtpCode();
  const expiresAt = now + config.otpExpirySeconds * 1000;
  const cooldownUntil = now + config.otpCooldownSeconds * 1000;

  const record = {
    phone,
    code,
    purpose,
    attempts: 0,
    expiresAt,
    cooldownUntil,
    createdAt: now
  };

  db.saveOtp(phone, record);

  const result = {
    phone,
    expiresInSeconds: config.otpExpirySeconds,
    cooldownSeconds: config.otpCooldownSeconds
  };

  // REAL_SMS_GATEWAY (Fast2SMS, DONE): real SMS delivery when the gateway is
  // configured. A failed dispatch FAILS the request with OTP_DISPATCH_FAILED
  // (invariant #3): the user must know the code never went out rather than
  // waiting for an SMS that will never arrive. Without the gateway the
  // request succeeds as before (dev mode / honest no-delivery limitation).
  const smsGateway = require('./smsGatewayService');
  if (smsGateway.isConfigured()) {
    const dispatch = await smsGateway.sendOtpSms({ to: phone, otp: code });
    if (!dispatch.delivered) {
      const error = new Error('Failed to dispatch the OTP SMS. Please try again shortly.');
      error.status = 502;
      error.code = 'OTP_DISPATCH_FAILED';
      throw error;
    }
    result.smsDispatched = true;
  }

  // Provide devOtp in non-production environments for automated testing
  if (config.isDev || config.isTest) {
    result.devOtp = code;
  }

  return result;
}

function verifyOtp(rawPhone, inputCode) {
  const phone = normalizePhone(rawPhone);
  if (!phone || !inputCode) {
    const error = new Error('Phone and 6-digit OTP code are required');
    error.status = 400;
    error.code = 'INVALID_PARAMETERS';
    throw error;
  }

  const record = db.getOtp(phone);
  const now = Date.now();

  // Check existence and expiration
  if (!record || now > record.expiresAt) {
    if (record) db.deleteOtp(phone);
    const error = new Error('OTP has expired or does not exist. Please request a new code.');
    error.status = 400;
    error.code = 'OTP_EXPIRED';
    throw error;
  }

  // Check attempt lockout
  if (record.attempts >= config.otpMaxAttempts) {
    db.deleteOtp(phone);
    const error = new Error('Too many failed attempts. Please request a new code.');
    error.status = 429;
    error.code = 'OTP_MAX_ATTEMPTS_EXCEEDED';
    throw error;
  }

  const cleanInput = String(inputCode).trim();

  // Check mismatch
  if (record.code !== cleanInput) {
    record.attempts += 1;
    if (record.attempts >= config.otpMaxAttempts) {
      db.deleteOtp(phone);
      const error = new Error('Too many failed attempts. Please request a new code.');
      error.status = 429;
      error.code = 'OTP_MAX_ATTEMPTS_EXCEEDED';
      throw error;
    }

    db.saveOtp(phone, record);
    const remaining = config.otpMaxAttempts - record.attempts;
    const error = new Error(`Invalid verification code. ${remaining} attempts remaining.`);
    error.status = 401;
    error.code = 'INVALID_OTP';
    error.remainingAttempts = remaining;
    throw error;
  }

  // Success: consume OTP immediately
  db.deleteOtp(phone);

  return {
    verified: true,
    phone
  };
}

module.exports = {
  sendOtp,
  verifyOtp,
  generateOtpCode
};
