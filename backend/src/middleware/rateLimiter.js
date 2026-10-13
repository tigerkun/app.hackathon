/**
 * Rate Limiter Middleware
 * In-memory sliding-window rate limiting with standard Retry-After and RateLimit headers.
 */

function createRateLimiter(options = {}) {
  const windowMs = options.windowMs || 60 * 1000; // 1 minute default
  const max = options.max || 100; // 100 requests per window
  const message = options.message || 'Too many requests, please try again later.';
  const keyGenerator = options.keyGenerator || ((req) => req.ip || req.connection.remoteAddress || '127.0.0.1');

  // Map<key, { count: number, resetTime: number }>
  const hits = new Map();

  // Periodic cleanup of stale buckets
  const cleanupInterval = setInterval(() => {
    const now = Date.now();
    for (const [key, data] of hits.entries()) {
      if (now > data.resetTime) {
        hits.delete(key);
      }
    }
  }, Math.min(windowMs, 60000));

  if (cleanupInterval.unref) {
    cleanupInterval.unref();
  }

  return function rateLimiter(req, res, next) {
    // If in test environment and skipInTest is configured
    if (process.env.NODE_ENV === 'test' && options.skipInTest) {
      return next();
    }

    const key = keyGenerator(req);
    const now = Date.now();
    let record = hits.get(key);

    if (!record || now > record.resetTime) {
      record = {
        count: 1,
        resetTime: now + windowMs
      };
      hits.set(key, record);
    } else {
      record.count += 1;
    }

    const remaining = Math.max(0, max - record.count);
    const resetSeconds = Math.ceil((record.resetTime - now) / 1000);

    res.setHeader('RateLimit-Limit', String(max));
    res.setHeader('RateLimit-Remaining', String(remaining));
    res.setHeader('RateLimit-Reset', String(resetSeconds));

    if (record.count > max) {
      res.setHeader('Retry-After', String(resetSeconds));
      return res.status(429).json({
        success: false,
        error: {
          code: 'RATE_LIMIT_EXCEEDED',
          message,
          details: [{ retryAfterSeconds: resetSeconds }]
        }
      });
    }

    next();
  };
}

// Preconfigured rate limiters
const globalLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 300,
  message: 'Global API rate limit exceeded.',
  skipInTest: true
});

const authLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 50,
  message: 'Too many authentication attempts. Please try again shortly.',
  skipInTest: true
});

module.exports = {
  createRateLimiter,
  globalLimiter,
  authLimiter
};
