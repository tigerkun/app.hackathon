/**
 * Centralized Error Handler Middleware
 * Normalizes all uncaught errors and 404 routes into standard SafeSphere JSON envelopes.
 */

function notFoundHandler(req, res) {
  res.status(404).json({
    success: false,
    error: {
      code: 'NOT_FOUND',
      message: `Endpoint ${req.method} ${req.originalUrl} not found`,
      details: []
    }
  });
}

function errorHandler(err, req, res, next) {
  const status = err.status || 500;
  const code = err.code || (status === 500 ? 'INTERNAL_SERVER_ERROR' : 'REQUEST_ERROR');
  const message = err.message || 'An unexpected error occurred';
  const details = err.details || [];

  if (err.retryAfter) {
    res.setHeader('Retry-After', String(err.retryAfter));
  }

  // Log 500 errors in development
  if (status >= 500 && process.env.NODE_ENV !== 'test') {
    console.error(`[Error 500] ${req.method} ${req.url}:`, err);
  }

  res.status(status).json({
    success: false,
    error: {
      code,
      message,
      details
    }
  });
}

module.exports = {
  notFoundHandler,
  errorHandler
};
