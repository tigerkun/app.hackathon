/**
 * Request Validation Middleware
 * Lightweight schema validations returning normalized 400 Bad Request envelopes with detailed field issues.
 */

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_REGEX = /^\+?[0-9\s\-()]{7,20}$/;

function formatValidationError(res, details) {
  return res.status(400).json({
    success: false,
    error: {
      code: 'VALIDATION_ERROR',
      message: 'Invalid request parameters',
      details
    }
  });
}

function validateRegister(req, res, next) {
  const { name, email, phone, password, pin } = req.body || {};
  const issues = [];

  if (!name || typeof name !== 'string' || name.trim().length < 2 || name.trim().length > 100) {
    issues.push({ field: 'name', issue: 'Name must be between 2 and 100 characters.' });
  }

  if (!email || typeof email !== 'string' || !EMAIL_REGEX.test(email.trim())) {
    issues.push({ field: 'email', issue: 'A valid email address is required.' });
  }

  if (!phone || typeof phone !== 'string' || !PHONE_REGEX.test(phone.trim())) {
    issues.push({ field: 'phone', issue: 'A valid phone number is required (at least 7 digits).' });
  }

  if (!password || typeof password !== 'string' || password.length < 8) {
    issues.push({ field: 'password', issue: 'Password must be at least 8 characters long.' });
  }

  if (pin !== undefined && pin !== null) {
    const pinStr = String(pin).trim();
    if (!/^\d{4,6}$/.test(pinStr)) {
      issues.push({ field: 'pin', issue: 'PIN must be between 4 and 6 numeric digits.' });
    }
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  next();
}

function validateLogin(req, res, next) {
  const body = req.body || {};
  const emailOrPhone = body.emailOrPhone || body.email_or_phone || body.email || body.phone;
  const password = body.password;
  const issues = [];

  if (!emailOrPhone || typeof emailOrPhone !== 'string' || !emailOrPhone.trim()) {
    issues.push({ field: 'emailOrPhone', issue: 'Email or phone number is required.' });
  }

  if (!password || typeof password !== 'string' || !password) {
    issues.push({ field: 'password', issue: 'Password is required.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  // Normalize onto req.body.emailOrPhone
  req.body.emailOrPhone = emailOrPhone.trim();
  next();
}

function validateLoginPin(req, res, next) {
  const body = req.body || {};
  const emailOrPhone = body.emailOrPhone || body.email_or_phone || body.email || body.phone;
  const pin = body.pin;
  const issues = [];

  if (!emailOrPhone || typeof emailOrPhone !== 'string' || !emailOrPhone.trim()) {
    issues.push({ field: 'emailOrPhone', issue: 'Email or phone number is required.' });
  }

  if (!pin || !/^\d{4,6}$/.test(String(pin).trim())) {
    issues.push({ field: 'pin', issue: 'A valid 4 to 6 digit numeric PIN is required.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  req.body.emailOrPhone = emailOrPhone.trim();
  req.body.pin = String(pin).trim();
  next();
}

function validateOtpSend(req, res, next) {
  const { phone } = req.body || {};
  const issues = [];

  if (!phone || typeof phone !== 'string' || !PHONE_REGEX.test(phone.trim())) {
    issues.push({ field: 'phone', issue: 'A valid phone number is required to send an OTP.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  req.body.phone = phone.trim();
  next();
}

function validateOtpVerify(req, res, next) {
  const { phone, otp } = req.body || {};
  const issues = [];

  if (!phone || typeof phone !== 'string' || !PHONE_REGEX.test(phone.trim())) {
    issues.push({ field: 'phone', issue: 'A valid phone number is required.' });
  }

  if (!otp || !/^\d{6}$/.test(String(otp).trim())) {
    issues.push({ field: 'otp', issue: 'A 6-digit numeric OTP is required.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  req.body.phone = phone.trim();
  req.body.otp = String(otp).trim();
  next();
}

function validateRefresh(req, res, next) {
  const body = req.body || {};
  const refreshToken = body.refreshToken || body.refresh_token;

  if (!refreshToken || typeof refreshToken !== 'string' || !refreshToken.trim()) {
    return formatValidationError(res, [
      { field: 'refreshToken', issue: 'Refresh token is required.' }
    ]);
  }

  req.body.refreshToken = refreshToken.trim();
  next();
}

function validateReportCreate(req, res, next) {
  const { description, location } = req.body || {};
  const issues = [];

  if (!description || typeof description !== 'string' || !description.trim()) {
    issues.push({ field: 'description', issue: 'Report description is required.' });
  }

  if (!location || typeof location !== 'string' || !location.trim()) {
    issues.push({ field: 'location', issue: 'Report location or landmark is required.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  next();
}

function validateSosTrigger(req, res, next) {
  const { latitude, longitude } = req.body || {};
  const issues = [];

  if (latitude === undefined || latitude === null || isNaN(Number(latitude))) {
    issues.push({ field: 'latitude', issue: 'Valid latitude coordinate is required.' });
  }

  if (longitude === undefined || longitude === null || isNaN(Number(longitude))) {
    issues.push({ field: 'longitude', issue: 'Valid longitude coordinate is required.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  next();
}

module.exports = {
  validateRegister,
  validateLogin,
  validateLoginPin,
  validateOtpSend,
  validateOtpVerify,
  validateRefresh,
  validateReportCreate,
  validateSosTrigger
};
