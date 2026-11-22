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

// M1.6b: Forgot-PIN reset — phone + OTP + new 4-6 digit PIN.
function validatePinReset(req, res, next) {
  const { phone, otp, newPin } = req.body || {};
  const issues = [];

  if (!phone || typeof phone !== 'string' || !PHONE_REGEX.test(phone.trim())) {
    issues.push({ field: 'phone', issue: 'A valid phone number is required.' });
  }

  if (!otp || !/^\d{6}$/.test(String(otp).trim())) {
    issues.push({ field: 'otp', issue: 'A 6-digit numeric OTP is required.' });
  }

  if (!newPin || !/^\d{4,6}$/.test(String(newPin).trim())) {
    issues.push({ field: 'newPin', issue: 'New PIN must be 4 to 6 numeric digits.' });
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  req.body.phone = phone.trim();
  req.body.otp = String(otp).trim();
  req.body.newPin = String(newPin).trim();
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
  const { description, location, photoBase64 } = req.body || {};
  const issues = [];

  if (!description || typeof description !== 'string' || !description.trim()) {
    issues.push({ field: 'description', issue: 'Report description is required.' });
  } else if (description.length > 2000) {
    issues.push({ field: 'description', issue: 'Report description must be at most 2000 characters.' });
  }

  if (!location || typeof location !== 'string' || !location.trim()) {
    issues.push({ field: 'location', issue: 'Report location or landmark is required.' });
  } else if (location.length > 200) {
    issues.push({ field: 'location', issue: 'Report location must be at most 200 characters.' });
  }

  // Coordinates are optional but must be real numbers within bounds when present.
  const lat = Number(req.body?.latitude);
  const lng = Number(req.body?.longitude);
  if (req.body?.latitude !== undefined && req.body?.latitude !== null
    && (!Number.isFinite(lat) || lat < -90 || lat > 90)) {
    issues.push({ field: 'latitude', issue: 'Valid latitude coordinate is required.' });
  }
  if (req.body?.longitude !== undefined && req.body?.longitude !== null
    && (!Number.isFinite(lng) || lng < -180 || lng > 180)) {
    issues.push({ field: 'longitude', issue: 'Valid longitude coordinate is required.' });
  }

  // Attachments: bounded array of URL strings or {type,url} objects. Without
  // this an authenticated user could persist arbitrary payloads served to
  // every feed reader (10MB body limit × N reports).
  if (req.body?.attachments !== undefined && req.body?.attachments !== null) {
    const atts = req.body.attachments;
    const validAttachment = (a) => {
      if (typeof a === 'string') {
        return a.length <= 2048 && (/^https?:\/\//i.test(a) || a.startsWith('data:image/'));
      }
      if (a && typeof a === 'object' && !Array.isArray(a)) {
        return typeof a.url === 'string' && a.url.length <= 2048
          && (/^https?:\/\//i.test(a.url) || a.url.startsWith('data:image/'))
          && (a.type === undefined || (typeof a.type === 'string' && a.type.length <= 50));
      }
      return false;
    };
    if (!Array.isArray(atts) || atts.length > 5 || !atts.every(validAttachment)) {
      issues.push({
        field: 'attachments',
        issue: 'Attachments must be an array of at most 5 image URLs or {type,url} objects.'
      });
    }
  }

  // A client-provided photoUrl bypasses the base64 image validation below —
  // only values derived from a validated photoBase64 payload may be used.
  if (req.body?.photoUrl !== undefined && req.body?.photoUrl !== null) {
    issues.push({ field: 'photoUrl', issue: 'photoUrl cannot be submitted directly. Send the image as photoBase64 instead.' });
  }

  if (photoBase64 !== undefined && photoBase64 !== null) {
    if (typeof photoBase64 !== 'string' || !photoBase64.trim()) {
      issues.push({ field: 'photoBase64', issue: 'Photo attachment must be a valid base64 string.' });
    } else {
      let rawBase64 = photoBase64.trim();
      let mimeType = null;
      const dataUrlMatch = rawBase64.match(/^data:image\/(jpeg|jpg|png);base64,(.+)$/i);
      if (dataUrlMatch) {
        mimeType = dataUrlMatch[1].toLowerCase() === 'jpg' ? 'jpeg' : dataUrlMatch[1].toLowerCase();
        rawBase64 = dataUrlMatch[2];
      }

      const approxBytes = Math.ceil((rawBase64.length * 3) / 4);
      if (approxBytes > 500 * 1024) {
        issues.push({ field: 'photoBase64', issue: 'Photo attachment exceeds 500KB maximum size.' });
      } else {
        try {
          const buffer = Buffer.from(rawBase64, 'base64');
          if (buffer.length > 500 * 1024) {
            issues.push({ field: 'photoBase64', issue: 'Photo attachment exceeds 500KB maximum size.' });
          } else {
            const isJpeg = buffer.length >= 3 && buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF;
            const isPng = buffer.length >= 4 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47;

            if (mimeType) {
              if ((mimeType === 'jpeg' && !isJpeg) || (mimeType === 'png' && !isPng)) {
                issues.push({ field: 'photoBase64', issue: 'Invalid image format. Only JPEG and PNG are supported.' });
              }
            } else {
              if (isJpeg) mimeType = 'jpeg';
              else if (isPng) mimeType = 'png';
              else {
                issues.push({ field: 'photoBase64', issue: 'Invalid image format. Only JPEG and PNG are supported.' });
              }
            }

            if (mimeType && issues.length === 0) {
              req.body.photoUrl = `data:image/${mimeType};base64,${rawBase64}`;
            }
          }
        } catch (_) {
          issues.push({ field: 'photoBase64', issue: 'Failed to decode photo base64 payload.' });
        }
      }
    }
  }

  if (issues.length > 0) {
    return formatValidationError(res, issues);
  }

  next();
}

function validateSosTrigger(req, res, next) {
  const { latitude, longitude } = req.body || {};
  const issues = [];

  const lat = Number(latitude);
  const lng = Number(longitude);

  if (latitude === undefined || latitude === null || !Number.isFinite(lat) || lat < -90 || lat > 90) {
    issues.push({ field: 'latitude', issue: 'Valid latitude coordinate is required.' });
  }

  if (longitude === undefined || longitude === null || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    issues.push({ field: 'longitude', issue: 'Valid longitude coordinate is required.' });
  }

  // Length caps on free-text and type fields (defense against oversized payloads).
  if (req.body?.notes !== undefined && req.body?.notes !== null) {
    if (typeof req.body.notes !== 'string') {
      issues.push({ field: 'notes', issue: 'SOS notes must be a string.' });
    } else if (req.body.notes.length > 500) {
      issues.push({ field: 'notes', issue: 'SOS notes must be at most 500 characters.' });
    }
  }

  if (req.body?.alertType !== undefined && req.body?.alertType !== null) {
    if (typeof req.body.alertType !== 'string') {
      issues.push({ field: 'alertType', issue: 'alertType must be a string.' });
    } else if (req.body.alertType.length > 40) {
      issues.push({ field: 'alertType', issue: 'alertType must be at most 40 characters.' });
    }
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
  validateSosTrigger,
  validatePinReset
};
