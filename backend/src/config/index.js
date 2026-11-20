/**
 * SafeSphere Backend Configuration
 * Centralized configuration loader with robust environment defaults.
 */

const path = require('path');

const INSECURE_SECRET_DENYLIST = new Set([
  'safesphere_dev_jwt_secret_key_2026_super_secure',
  'safesphere_dev_jwt_refresh_secret_key_2026_super_secure',
  'safesphere_production_super_secret_jwt_key_2026',
  'default_secret',
  'secret',
  'secretkey',
  'password',
  'changeme',
  '123456',
  'admin',
  'jwt_secret'
]);

function validateJwtSecretHygiene({ jwtSecret, refreshSecret, nodeEnv } = {}) {
  const env = nodeEnv || process.env.NODE_ENV || 'development';
  const isProd = env === 'production';
  if (!isProd) {
    return { valid: true, warnings: [] };
  }

  const errors = [];
  if (!jwtSecret || typeof jwtSecret !== 'string' || !jwtSecret.trim()) {
    errors.push('JWT_SECRET must be explicitly set and non-empty in production');
  }
  if (!refreshSecret || typeof refreshSecret !== 'string' || !refreshSecret.trim()) {
    errors.push('JWT_REFRESH_SECRET must be explicitly set and non-empty in production');
  }
  if (jwtSecret && typeof jwtSecret === 'string' && INSECURE_SECRET_DENYLIST.has(jwtSecret.trim().toLowerCase())) {
    errors.push('JWT_SECRET matches a known insecure default secret');
  }
  if (refreshSecret && typeof refreshSecret === 'string' && INSECURE_SECRET_DENYLIST.has(refreshSecret.trim().toLowerCase())) {
    errors.push('JWT_REFRESH_SECRET matches a known insecure default secret');
  }
  if (
    jwtSecret &&
    refreshSecret &&
    typeof jwtSecret === 'string' &&
    typeof refreshSecret === 'string' &&
    jwtSecret.trim() === refreshSecret.trim()
  ) {
    errors.push('JWT_SECRET and JWT_REFRESH_SECRET must not be identical');
  }
  if (jwtSecret && typeof jwtSecret === 'string' && jwtSecret.trim().length < 32) {
    errors.push('JWT_SECRET must be at least 32 characters in production');
  }
  if (refreshSecret && typeof refreshSecret === 'string' && refreshSecret.trim().length < 32) {
    errors.push('JWT_REFRESH_SECRET must be at least 32 characters in production');
  }

  if (errors.length > 0) {
    const err = new Error(`JWT Secret Hygiene Validation Failed: ${errors.join('; ')}`);
    err.code = 'INSECURE_JWT_CONFIG';
    err.details = errors;
    throw err;
  }

  return { valid: true, warnings: [] };
}

const nodeEnv = process.env.NODE_ENV || 'development';
const isProduction = nodeEnv === 'production';
const isTest = nodeEnv === 'test';
const isDev = !isProduction;

const isTestRunner = isTest || Boolean(process.env.NODE_TEST_CONTEXT);
const defaultDbPath = isTestRunner
  ? ':memory:'
  : path.resolve(__dirname, '../../data/safesphere.db');
const dbPath = process.env.DB_PATH || defaultDbPath;

// Demo Mode: Disabled by default in production. Enabled by default in dev/test.
// Explicit process.env.DEMO_MODE overrides defaults ('true'/'1' or 'false'/'0').
const demoModeEnv = process.env.DEMO_MODE;
const isDemoMode = (demoModeEnv !== undefined)
  ? (demoModeEnv === 'true' || demoModeEnv === '1')
  : (!isProduction);

const rawJwtSecret = process.env.JWT_SECRET;
const rawRefreshSecret = process.env.JWT_REFRESH_SECRET;

// In production, validate JWT secrets immediately upon config loading
if (isProduction) {
  validateJwtSecretHygiene({
    jwtSecret: rawJwtSecret,
    refreshSecret: rawRefreshSecret,
    nodeEnv
  });

  const missingProdVars = [];
  if (!process.env.CORS_ORIGIN) missingProdVars.push('CORS_ORIGIN');
  if (!process.env.DB_PATH) missingProdVars.push('DB_PATH');
  if (!process.env.PORT) missingProdVars.push('PORT');

  if (missingProdVars.length > 0) {
    console.warn(`[WARNING] Missing recommended production environment variables: ${missingProdVars.join(', ')}`);
  }

  if (!process.env.CORS_ORIGIN) {
    console.warn('[WARNING] CORS_ORIGIN is not set in production. Defaulting to "*". For security, set CORS_ORIGIN to your frontend domain.');
  }
}

const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv,
  jwtSecret: rawJwtSecret || (isProduction ? undefined : 'safesphere_dev_jwt_secret_key_2026_super_secure'),
  refreshSecret: rawRefreshSecret || (isProduction ? undefined : 'safesphere_dev_jwt_refresh_secret_key_2026_super_secure'),
  saltRounds: parseInt(process.env.SALT_ROUNDS, 10) || (isTest ? 8 : 10),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || 900, // 15 minutes (seconds)
  refreshExpiresIn: process.env.REFRESH_EXPIRES_IN || 604800, // 7 days (seconds)
  otpExpirySeconds: 300, // 5 minutes
  otpCooldownSeconds: 60, // 60 seconds
  otpMaxAttempts: 3,
  escalateAfterMs: parseInt(process.env.ESCALATE_AFTER_MS || '600000', 10),
  escalationTickMs: parseInt(process.env.ESCALATION_TICK_MS || '60000', 10),
  corsOrigin: process.env.CORS_ORIGIN || '*',
  dbPath,
  isTest,
  isDev,
  isProduction,
  isDemoMode,
  validateJwtSecretHygiene,
  INSECURE_SECRET_DENYLIST
};

module.exports = config;
