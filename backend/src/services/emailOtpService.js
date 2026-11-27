/**
 * Email OTP Service (Resend)
 *
 * Primary zero-cost OTP delivery channel via Resend's REST API
 * (https://api.resend.com/emails — 100 emails/day, 3,000/month free tier).
 * Uses Node's built-in fetch with no extra SDK dependency.
 *
 * Configuration (env only — keys are never logged or returned):
 *   RESEND_API_KEY       Resend API bearer token
 *   OTP_FROM_EMAIL       Verified sender address (default onboarding@resend.dev)
 *   EMAIL_OTP_DAILY_CAP  Optional per-email daily cap override (default 5)
 *
 * Honesty rules (AGENTS.md invariant #3): returns delivered: true ONLY on HTTP 2xx.
 */

const { db } = require('../data/store');

const RESEND_API_URL = 'https://api.resend.com/emails';
const REQUEST_TIMEOUT_MS = 10000;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DEFAULT_DAILY_CAP = 5;

function getApiKey() {
  return (process.env.RESEND_API_KEY || '').trim();
}

function getFromEmail() {
  const configured = (process.env.OTP_FROM_EMAIL || '').trim();
  return configured || 'SafeSphere <onboarding@resend.dev>';
}

function getDailyCap() {
  const parsed = parseInt(process.env.EMAIL_OTP_DAILY_CAP || '', 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_DAILY_CAP;
}

function isConfigured() {
  return getApiKey().length > 0;
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
  const subject = 'Your SafeSphere verification code';
  const text = [
    'SafeSphere Personal Safety Verification',
    '',
    `Your verification code is ${safeCode}.`,
    '',
    'This code expires in 10 minutes.',
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
      This code expires in 10 minutes.
    </p>
    <p style="margin:0;font-size:12px;color:#64748B;">
      If you didn't request this, you can safely ignore this email.
    </p>
  </div>
</body>
</html>`.trim();

  return { subject, text, html };
}

/**
 * Dispatches a 6-digit OTP email through Resend.
 * @returns {Promise<{delivered: boolean, id?: string, maskedEmail?: string, error?: string, skipped?: boolean}>}
 */
async function sendOtpEmail({ to, otp }) {
  const email = normalizeEmail(to);
  if (!email) {
    return { delivered: false, skipped: true, error: 'Valid recipient email is required' };
  }
  if (!isConfigured()) {
    return { delivered: false, skipped: true, maskedEmail: maskEmail(email), error: 'RESEND_API_KEY not configured' };
  }

  checkDailyLimit(email);
  const day = currentUtcDay();
  db.incrementEmailOtpCount(email, day);

  const { subject, text, html } = buildOtpEmailContent({ otp });

  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${getApiKey()}`,
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
      return {
        delivered: false,
        maskedEmail: maskEmail(email),
        error: `resend dispatch failed (HTTP ${res.status})`
      };
    }

    return {
      delivered: true,
      id: decoded && decoded.id ? String(decoded.id) : undefined,
      maskedEmail: maskEmail(email)
    };
  } catch (_) {
    return {
      delivered: false,
      maskedEmail: maskEmail(email),
      error: 'resend network failure'
    };
  }
}

module.exports = {
  isConfigured,
  normalizeEmail,
  maskEmail,
  checkDailyLimit,
  buildOtpEmailContent,
  sendOtpEmail,
  getDailyCap
};
