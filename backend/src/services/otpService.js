/**
 * OTP Service
 * Handles cryptographic 6-digit random OTP generation, 60s cooldown throttling,
 * 3-attempt lockout security, and development bypass support.
 */

const crypto = require('crypto');
const config = require('../config');
const { db } = require('../data/store');
const { normalizePhone } = require('../models/userModel');
const emailOtpService = require('./emailOtpService');

function generateOtpCode() {
  return String(crypto.randomInt(100000, 1000000));
}

async function sendOtp(rawPhone, purpose = 'login', rawEmail = null) {
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

  // Prefer email passed explicitly or stored on the matching user account.
  const explicitEmail = emailOtpService.normalizeEmail(rawEmail);
  const accountEmail = !explicitEmail
    ? emailOtpService.normalizeEmail(db.findUserByPhone(phone)?.email)
    : null;
  const targetEmail = explicitEmail || accountEmail;

  const emailReady = emailOtpService.isConfigured() && Boolean(targetEmail);
  if (emailReady) {
    emailOtpService.checkDailyLimit(targetEmail);
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
    cooldownSeconds: config.otpCooldownSeconds,
    channel: 'unavailable',
    emailDispatched: false
  };

  // Primary free-tier OTP delivery via Resend email when RESEND_API_KEY and a
  // recipient email exist. Production fails honestly with 502 on upstream
  // failure; non-prod falls back to devOtp cleanly.
  if (emailReady) {
    const dispatch = await emailOtpService.sendOtpEmail({ to: targetEmail, otp: code });
    result.maskedEmail = dispatch.maskedEmail;
    if (dispatch.delivered) {
      result.emailDispatched = true;
      result.channel = 'email';
      return result;
    }

    if (config.isProduction || (!config.isDev && !config.isTest)) {
      db.deleteOtp(phone);
      const error = new Error('Failed to send verification email. Please try again shortly.');
      error.status = 502;
      error.code = 'OTP_DISPATCH_FAILED';
      throw error;
    }

    result.channel = 'dev_fallback';
    result.fallbackReason = dispatch.error || 'email delivery failed';
    result.devOtp = code;
    return result;
  }

  // Secondary/legacy SMS gateway path (Fast2SMS / Textlocal when configured).
  const smsGateway = require('./smsGatewayService');
  if (smsGateway.isOtpConfigured()) {
    const dispatch = await smsGateway.sendOtpSms({ to: phone, otp: code });
    if (!dispatch.delivered) {
      const error = new Error('Failed to dispatch the OTP SMS. Please try again shortly.');
      error.status = 502;
      error.code = 'OTP_DISPATCH_FAILED';
      throw error;
    }
    result.smsDispatched = true;
    result.channel = 'sms';
    return result;
  }

  // Unconfigured fallback: expose devOtp ONLY in non-production environments.
  if (!config.isProduction && (config.isDev || config.isTest)) {
    result.channel = 'dev_fallback';
    result.devOtp = code;
  }

  return result;
}

function canonicalPurpose(purpose) {
  const normalized = String(purpose || '').trim().toLowerCase();
  if (!normalized) return '';
  if (normalized === 'pin_reset' || normalized === 'pin-reset' || normalized === 'reset_pin') {
    return 'pin_reset';
  }
  if (
    normalized === 'login' ||
    normalized === 'verify' ||
    normalized === 'verification' ||
    normalized === 'signup' ||
    normalized === 'register'
  ) {
    return 'auth_verify';
  }
  return normalized;
}

function verifyOtp(rawPhone, inputCode, expectedPurpose = null) {
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

  // Check mismatch BEFORE purpose check so attackers cannot probe OTP purpose without the code
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

  if (expectedPurpose !== null && expectedPurpose !== undefined && String(expectedPurpose).trim() !== '') {
    const expectedCanon = canonicalPurpose(expectedPurpose);
    const actualCanon = canonicalPurpose(record.purpose);
    if (!actualCanon || actualCanon !== expectedCanon) {
      const error = new Error('This verification code was issued for a different action. Please request a new code.');
      error.status = 400;
      error.code = 'OTP_PURPOSE_MISMATCH';
      throw error;
    }
  }

  // Success: consume OTP immediately
  db.deleteOtp(phone);

  return {
    verified: true,
    phone,
    purpose: record.purpose
  };
}

module.exports = {
  sendOtp,
  verifyOtp,
  generateOtpCode,
  canonicalPurpose
};
