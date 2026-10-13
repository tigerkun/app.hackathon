/**
 * Auth Controller
 * Handles user registration, multi-modal login (password, PIN, OTP, biometrics),
 * token refresh, protected profile retrieval, and session logout.
 */

const authService = require('../services/authService');
const otpService = require('../services/otpService');

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
    const result = otpService.sendOtp(phone, purpose);

    res.status(200).json({
      success: true,
      message: `OTP sent successfully to ${result.phone}`,
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

module.exports = {
  register,
  login,
  loginPin,
  sendOtp,
  verifyOtp,
  refresh,
  me,
  logout,
  registerBiometrics,
  loginBiometrics
};
