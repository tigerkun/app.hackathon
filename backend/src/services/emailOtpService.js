/**
 * Email OTP Service (Resend primary, Brevo fallback)
 *
 * Primary zero-cost OTP delivery channel via Resend's REST API
 * (https://api.resend.com/emails — 100 emails/day, 3,000/month free tier),
 * with automatic fallback to Brevo (https://api.brevo.com/v3/smtp/email)
 * when BREVO_API_KEY is configured instead.
 * Uses Node's built-in fetch with no extra SDK dependency.
 *
 * Configuration (env only — keys are never logged or returned):
 *   RESEND_API_KEY       Resend API bearer token (preferred when set)
 *   OTP_FROM_EMAIL       Verified sender address (default onboarding@resend.dev)
 *   BREVO_API_KEY        Optional Brevo v3 SMTP API key fallback
 *   BREVO_SENDER_EMAIL   Sender email for Brevo (or falls back to OTP_FROM_EMAIL)
 *   EMAIL_OTP_DAILY_CAP  Optional per-email daily cap override (default 5)
 *
 * Honesty rules (AGENTS.md invariant #3): returns delivered: true ONLY on HTTP 2xx.
 */

const config = require('../config');
const { db } = require('../data/store');

const RESEND_API_URL = 'https://api.resend.com/emails';
const BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';
const REQUEST_TIMEOUT_MS = 10000;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DEFAULT_DAILY_CAP = 5;

function getResendApiKey() {
  return (process.env.RESEND_API_KEY || '').trim();
}

function getBrevoApiKey() {
  return (process.env.BREVO_API_KEY || '').trim();
}

function getFromEmail() {
  const configured = (process.env.OTP_FROM_EMAIL || '').trim();
  return configured || 'SafeSphere <onboarding@resend.dev>';
}

function getBrevoFromEmail() {
  const explicit = (process.env.BREVO_SENDER_EMAIL || '').trim();
  const fallback = (process.env.OTP_FROM_EMAIL || '').trim();
  const raw = explicit || fallback;
  if (!raw) return null;
  const match = raw.match(/<([^>]+)>/);
  const extracted = match ? match[1].trim() : raw;
  const normalized = normalizeEmail(extracted);
  if (!explicit && normalized === 'onboarding@resend.dev') {
    return null;
  }
  return normalized;
}

function isResendConfigured() {
  return getResendApiKey().length > 0;
}

function isBrevoConfigured() {
  return getBrevoApiKey().length > 0 && Boolean(getBrevoFromEmail());
}

function getConfiguredProviders() {
  const providers = [];
  if (isResendConfigured()) providers.push('resend');
  if (isBrevoConfigured()) providers.push('brevo');
  return providers;
}

function getProvider() {
  return getConfiguredProviders()[0] || null;
}

function getDailyCap() {
  const parsed = parseInt(process.env.EMAIL_OTP_DAILY_CAP || '', 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_DAILY_CAP;
}

function isConfigured() {
  return getProvider() !== null;
}

function normalizeEmail(rawEmail) {
  if (!rawEmail || typeof rawEmail !== 'string') return null;
  const trimmed = rawEmail.trim().toLowerCase();
  if (!trimmed || !EMAIL_REGEX.test(trimmed)) return null;
  return trimmed;
}

function maskEmail(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  const [local, domain] = normalized.split('@');
  if (!domain) return null;
  const visible = local.length <= 2 ? local.slice(0, 1) : local.slice(0, 2);
  return `${visible}***@${domain}`;
}

function currentUtcDay() {
  return new Date().toISOString().slice(0, 10);
}

function checkDailyLimit(rawEmail) {
  const email = normalizeEmail(rawEmail);
  if (!email) return { allowed: false, count: 0, limit: getDailyCap() };
  const limit = getDailyCap();
  const count = db.getEmailOtpCount(email, currentUtcDay());
  if (count >= limit) {
    const error = new Error(`Daily email verification limit (${limit}/day) reached. Please try again tomorrow.`);
    error.status = 429;
    error.code = 'EMAIL_OTP_DAILY_LIMIT';
    throw error;
  }
  return { allowed: true, count, limit };
}

function buildOtpEmailContent({ otp }) {
  const safeCode = String(otp || '').replace(/[^0-9]/g, '').slice(0, 6);
  const expiryMinutes = Math.max(1, Math.round((config.otpExpirySeconds || 300) / 60));
  const subject = 'Your SafeSphere verification code';
  const text = [
    'SafeSphere Personal Safety Verification',
    '',
    `Your verification code is ${safeCode}.`,
    '',
    `This code expires in ${expiryMinutes} minutes.`,
    "If you didn't request this, you can safely ignore this email."
  ].join('\n');

  const html = `
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>SafeSphere Verification Code</title></head>
<body style="margin:0;padding:24px;background:#0B0F1A;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#FFFFFF;">
  <div style="max-width:480px;margin:0 auto;background:#111827;border:1px solid rgba(47,224,201,0.3);border-radius:14px;padding:28px;">
    <div style="font-size:20px;font-weight:700;color:#2FE0C9;margin-bottom:12px;">SafeSphere</div>
    <p style="margin:0 0 16px;font-size:15px;color:#E2E8F0;line-height:1.5;">
      Your verification code is <strong style="color:#FFFFFF;font-size:20px;letter-spacing:3px;">${safeCode}</strong>
    </p>
    <div style="margin:18px 0;padding:14px;background:#0B0F1A;border-radius:10px;text-align:center;font-size:28px;font-weight:800;letter-spacing:6px;color:#2FE0C9;">
      ${safeCode}
    </div>
    <p style="margin:0 0 10px;font-size:13px;color:#94A3B8;">
      This code expires in ${expiryMinutes} minutes.
    </p>
    <p style="margin:0;font-size:12px;color:#64748B;">
      If you didn't request this, you can safely ignore this email.
    </p>
  </div>
</body>
</html>`.trim();

  return { subject, text, html };
}

async function dispatchWithResend({ email, subject, text, html }) {
  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${getResendApiKey()}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: getFromEmail(),
        to: [email],
        subject,
        text,
        html
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
    });
    let decoded = null;
    try { decoded = await res.json(); } catch (_) { decoded = null; }
    if (!res.ok) {
      return { delivered: false, provider: 'resend', error: `resend dispatch failed (HTTP ${res.status})` };
    }
    return {
      delivered: true,
      provider: 'resend',
      id: decoded && decoded.id ? String(decoded.id) : undefined
    };
  } catch (_) {
    return { delivered: false, provider: 'resend', error: 'resend network failure' };
  }
}

async function dispatchWithBrevo({ email, subject, text, html }) {
  try {
    const res = await fetch(BREVO_API_URL, {
      method: 'POST',
      headers: {
        'api-key': getBrevoApiKey(),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        sender: { name: 'SafeSphere', email: getBrevoFromEmail() },
        to: [{ email }],
        subject,
        textContent: text,
        htmlContent: html
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
    });
    let decoded = null;
    try { decoded = await res.json(); } catch (_) { decoded = null; }
    if (!res.ok) {
      return { delivered: false, provider: 'brevo', error: `brevo dispatch failed (HTTP ${res.status})` };
    }
    return {
      delivered: true,
      provider: 'brevo',
      id: decoded && (decoded.messageId || decoded.id) ? String(decoded.messageId || decoded.id) : undefined
    };
  } catch (_) {
    return { delivered: false, provider: 'brevo', error: 'brevo network failure' };
  }
}

/**
 * Dispatches a 6-digit OTP email through Resend (primary) with automatic runtime
 * failover to Brevo (secondary) when both are configured.
 * @returns {Promise<{delivered: boolean, provider?: string, id?: string, maskedEmail?: string, error?: string, skipped?: boolean, fallbackFrom?: string}>}
 */
async function sendOtpEmail({ to, otp }) {
  const email = normalizeEmail(to);
  if (!email) {
    return { delivered: false, skipped: true, error: 'Valid recipient email is required' };
  }
  const providers = getConfiguredProviders();
  if (providers.length === 0) {
    return { delivered: false, skipped: true, maskedEmail: maskEmail(email), error: 'Email OTP provider not configured' };
  }

  checkDailyLimit(email);
  const day = currentUtcDay();
  db.incrementEmailOtpCount(email, day);

  const { subject, text, html } = buildOtpEmailContent({ otp });
  const masked = maskEmail(email);
  const failures = [];

  for (const provider of providers) {
    const attempt = provider === 'resend'
      ? await dispatchWithResend({ email, subject, text, html })
      : await dispatchWithBrevo({ email, subject, text, html });

    if (attempt.delivered) {
      return {
        delivered: true,
        provider: attempt.provider,
        id: attempt.id,
        maskedEmail: masked,
        ...(failures.length > 0 ? { fallbackFrom: failures[0].provider } : {})
      };
    }

    failures.push({ provider, error: attempt.error });
  }

  return {
    delivered: false,
    provider: failures[failures.length - 1].provider,
    maskedEmail: masked,
    error: failures.map((f) => f.error).join('; ')
  };
}

module.exports = {
  isConfigured,
  getProvider,
  getConfiguredProviders,
  normalizeEmail,
  maskEmail,
  checkDailyLimit,
  buildOtpEmailContent,
  sendOtpEmail,
  getDailyCap
};
