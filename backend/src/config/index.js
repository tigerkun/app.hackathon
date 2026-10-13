/**
 * SafeSphere Backend Configuration
 * Centralized configuration loader with robust environment defaults.
 */

const path = require('path');

const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  jwtSecret: process.env.JWT_SECRET || 'safesphere_dev_jwt_secret_key_2026_super_secure',
  refreshSecret: process.env.JWT_REFRESH_SECRET || 'safesphere_dev_jwt_refresh_secret_key_2026_super_secure',
  saltRounds: parseInt(process.env.SALT_ROUNDS, 10) || (process.env.NODE_ENV === 'test' ? 8 : 10),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || 900, // 15 minutes (seconds)
  refreshExpiresIn: process.env.REFRESH_EXPIRES_IN || 604800, // 7 days (seconds)
  otpExpirySeconds: 300, // 5 minutes
  otpCooldownSeconds: 60, // 60 seconds
  otpMaxAttempts: 3,
  corsOrigin: process.env.CORS_ORIGIN || '*',
  isTest: process.env.NODE_ENV === 'test',
  isDev: (process.env.NODE_ENV || 'development') !== 'production'
};

module.exports = config;
