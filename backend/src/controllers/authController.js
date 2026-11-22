/**
 * Auth Controller
 * Handles user registration, multi-modal login (password, PIN, OTP, biometrics),
 * token refresh, protected profile retrieval, and session logout.
 */

const authService = require('../services/authService');
const otpService = require('../services/otpService');
const config = require('../config');

async function register(req, res, next) {
  try {
    const { name, email, phone, password, pin, emergencyContact, emergencyContacts } = req.body;
    const result = await authService.register({
      name,
      email,
      phone,
      password,
      pin,
      emergencyContact,
      emergencyContacts
    });

    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      data: result,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      tokenType: result.tokenType,
      expiresIn: result.expiresIn,
      user: result.user
    });
  } catch (err) {
    next(err);
  }
}

async function login(req, res, next) {
  try {
    const { emailOrPhone, password } = req.body;
    const userAgent = req.headers['user-agent'] || 'unknown';
    const ipAddress = req.ip || req.connection.remoteAddress || '127.0.0.1';

    const result = await authService.login({
      emailOrPhone,
      password,
      userAgent,
      ipAddress
    });

    res.status(200).json({
      success: true,
      message: 'Authentication successful',
      data: result,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      tokenType: result.tokenType,
      expiresIn: result.expiresIn,
      user: result.user
    });
  } catch (err) {
    next(err);
  }
}

async function loginPin(req, res, next) {
  try {
    const { emailOrPhone, pin } = req.body;
    const userAgent = req.headers['user-agent'] || 'unknown';
    const ipAddress = req.ip || req.connection.remoteAddress || '127.0.0.1';

    const result = await authService.loginPin({
      emailOrPhone,
      pin,
      userAgent,
      ipAddress
    });

    res.status(200).json({
      success: true,
      message: 'PIN authentication successful',
      data: result,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      tokenType: result.tokenType,
      expiresIn: result.expiresIn,
      user: result.user
    });
  } catch (err) {
    next(err);
  }
}

async function sendOtp(req, res, next) {
  try {
    const { phone, purpose } = req.body;
    const result = await otpService.sendOtp(phone, purpose);

    // Honest delivery copy (invariant #3): only claim "sent" when the SMS
    // gateway actually dispatched. Without SMS_API_KEY + an OTP template the
    // code is merely generated and cannot reach the user.
    const message = result.smsDispatched
      ? `OTP sent successfully to ${result.phone}`
      : `OTP generated for ${result.phone} — SMS delivery is not configured on this deployment, so the code cannot reach you. Use password or PIN login instead.`;

    res.status(200).json({
      success: true,
      message,
      smsDelivery: result.smsDispatched ? 'dispatched' : 'unavailable',
      data: result,
      phone: result.phone,
      expiresInSeconds: result.expiresInSeconds,
      cooldownSeconds: result.cooldownSeconds,
      devOtp: result.devOtp
    });
  } catch (err) {
    next(err);
  }
}

async function verifyOtp(req, res, next) {
  try {
    const { phone, otp } = req.body;
    const userAgent = req.headers['user-agent'] || 'unknown';
    const ipAddress = req.ip || req.connection.remoteAddress || '127.0.0.1';

    const result = await authService.verifyOtpAndLogin({
      phone,
      otp,
      userAgent,
      ipAddress
    });

    res.status(200).json({
      success: true,
      message: 'OTP verified successfully',
      data: result,
      verified: result.verified,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      user: result.user
    });
  } catch (err) {
    next(err);
  }
}

/**
 * M2.2: Aadhaar-lite abuse-prevention link — stores ONLY a salted SHA-256
 * hash of the last 4 digits. Never the full Aadhaar, never plaintext.
 * Consent copy lives in the client dialog that calls this endpoint.
 */
async function linkAadhaarLast4(req, res, next) {
  try {
    const { aadhaarLast4 } = req.body || {};
    if (!aadhaarLast4 || !/^\d{4}$/.test(String(aadhaarLast4).trim())) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'aadhaarLast4 must be exactly 4 digits.',
          details: []
        }
      });
    }

    const crypto = require('crypto');
    const { db } = require('../data/store');
    // Deterministic keyed hash (HMAC): identical last-4 values produce identical
    // hashes across accounts, so moderators can actually detect ban evasion —
    // a per-user random salt made the stored value useless for that purpose.
    // Last-4 is only 10k possibilities, so this remains a weak signal for
    // review, never proof of identity.
    const hashKey = process.env.AADHAAR_HASH_SECRET || config.jwtSecret;
    const hash = crypto
      .createHmac('sha256', String(hashKey))
      .update(`aadhaar-last4:${String(aadhaarLast4).trim()}`)
      .digest('hex');

    db.updateUser(req.userId, {
      aadhaarLast4Salt: 'hmac-v1',
      aadhaarLast4Hash: hash
    });

    const duplicates = db.countUsersWithAadhaarHash(hash, req.userId);

    res.status(200).json({
      success: true,
      message:
        'Linked. Stored only as a keyed hash — a weak signal moderators use for abuse review, not verified identity.',
      data: { aadhaarLinked: true, duplicateAccounts: duplicates }
    });
  } catch (err) {
    next(err);
  }
}

/**
 * M1.6b: Forgot-PIN recovery — phone + OTP + new PIN resets the account PIN
 * (bcrypt-hashed) and revokes all pre-reset sessions.
 */
async function resetPin(req, res, next) {
  try {
    const { phone, otp, newPin } = req.body;
    const result = await authService.resetPinWithOtp({ phone, otp, newPin });

    res.status(200).json({
      success: true,
      message: 'PIN reset successfully. Log in with your new PIN.',
      data: result
    });
  } catch (err) {
    next(err);
  }
}

async function refresh(req, res, next) {
  try {
    const { refreshToken } = req.body;
    const result = await authService.refreshSession(refreshToken);

    res.status(200).json({
      success: true,
      message: 'Token refreshed successfully',
      data: result,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      tokenType: result.tokenType,
      expiresIn: result.expiresIn
    });
  } catch (err) {
    next(err);
  }
}

async function me(req, res, next) {
  try {
    // req.user populated by requireAuth middleware
    res.status(200).json({
      success: true,
      data: req.user,
      user: req.user
    });
  } catch (err) {
    next(err);
  }
}

async function logout(req, res, next) {
  try {
    const sessionId = req.sessionId;
    const refreshToken = (req.body && req.body.refreshToken) || null;

    await authService.logout(sessionId, refreshToken);

    res.status(200).json({
      success: true,
      message: 'Logged out successfully'
    });
  } catch (err) {
    next(err);
  }
}

async function registerBiometrics(req, res, next) {
  try {
    const userId = req.userId;
    const { biometricToken } = req.body;

    if (!biometricToken) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'biometricToken is required',
          details: []
        }
      });
    }

    const updatedUser = await authService.registerBiometrics(userId, biometricToken);

    res.status(200).json({
      success: true,
      message: 'Biometric credentials registered successfully',
      data: updatedUser
    });
  } catch (err) {
    next(err);
  }
}

async function loginBiometrics(req, res, next) {
  try {
    const { biometricToken } = req.body;
    const userAgent = req.headers['user-agent'] || 'unknown';
    const ipAddress = req.ip || req.connection.remoteAddress || '127.0.0.1';

    const result = await authService.loginBiometrics({
      biometricToken,
      userAgent,
      ipAddress
    });

    res.status(200).json({
      success: true,
      message: 'Biometric authentication successful',
      data: result,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      user: result.user
    });
  } catch (err) {
    next(err);
  }
}

async function deleteMe(req, res, next) {
  try {
    const userId = req.userId || (req.user && req.user.id);
    if (!userId) {
      return res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHORIZED',
          message: 'Authentication is required to delete account',
          details: []
        }
      });
    }

    const { pin } = req.body || {};
    const { db } = require('../data/store');
    const user = db.findUserById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'USER_NOT_FOUND',
          message: 'User account not found',
          details: []
        }
      });
    }

    // If account has a PIN set, re-auth PIN verification is required
    if (user.pinHash || user.pin) {
      if (!pin) {
        return res.status(400).json({
          success: false,
          error: {
            code: 'PIN_REQUIRED',
            message: 'PIN is required to confirm account deletion',
            details: []
          }
        });
      }
      const bcrypt = require('bcryptjs');
      const pinMatches = user.pinHash
        ? await bcrypt.compare(String(pin), user.pinHash)
        : (user.pin && user.pin === String(pin));
      if (!pinMatches) {
        return res.status(401).json({
          success: false,
          error: {
            code: 'INVALID_PIN',
            message: 'Incorrect security PIN for account deletion',
            details: []
          }
        });
      }
    }

    await authService.deleteAccount(userId);

    res.status(200).json({
      success: true,
      message: 'User account, sessions, alerts, and tracking data deleted successfully'
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  register,
  login,
  loginPin,
  sendOtp,
  verifyOtp,
  resetPin,
  linkAadhaarLast4,
  refresh,
  me,
  logout,
  registerBiometrics,
  loginBiometrics,
  deleteMe
};
