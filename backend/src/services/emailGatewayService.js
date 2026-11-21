/**
 * Email Gateway Service
 * Provider: Brevo (formerly Sendinblue) — free tier 300 emails/day, no card.
 *
 * Configuration (env only — the key is never committed or returned):
 *   BREVO_API_KEY        Brevo v3 API key (xkeysib-...) — required to enable
 *   BREVO_SENDER_EMAIL   validated sender address (default: the account's
 *                        signup email tejasgaur94@gmail.com)
 *
 * Used for SOS emergency-contact notifications: contacts that carry an email
 * address receive the alert by email alongside any SMS attempt. Every
 * dispatch outcome is reported truthfully (invariant #3).
 */

const BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';
const REQUEST_TIMEOUT_MS = 10000;

const DEFAULT_SENDER = 'tejasgaur94@gmail.com';

function getApiKey() {
  return (process.env.BREVO_API_KEY || '').trim();
}

function getSenderEmail() {
  return (process.env.BREVO_SENDER_EMAIL || DEFAULT_SENDER).trim();
}

function isConfigured() {
  return getApiKey().length > 0;
}

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidEmail(raw) {
  return typeof raw === 'string' && EMAIL_REGEX.test(raw.trim());
}

/**
 * Sends a transactional email via Brevo v3.
 * @returns {Promise<{delivered: boolean, messageId?: string, error?: string}>}
 */
async function sendEmail({ to, subject, text }) {
  if (!isConfigured()) {
    return { delivered: false, error: 'Email gateway not configured' };
  }
  if (!isValidEmail(to)) {
    return { delivered: false, error: 'Invalid recipient email' };
  }

  const res = await fetch(BREVO_API_URL, {
    method: 'POST',
    headers: {
      'api-key': getApiKey(),
      'Content-Type': 'application/json',
      Accept: 'application/json'
    },
    body: JSON.stringify({
      sender: { name: 'SafeSphere', email: getSenderEmail() },
      to: [{ email: to.trim() }],
      subject: String(subject).slice(0, 150),
      textContent: String(text).slice(0, 1000)
    }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });

  let decoded = null;
  try { decoded = await res.json(); } catch (_) { decoded = null; }

  // Brevo returns 201 with { messageId } on success.
  const succeeded = res.ok && decoded && typeof decoded.messageId === 'string';
  if (!succeeded) {
    return {
      delivered: false,
      error: `brevo email dispatch failed (HTTP ${res.status})`
    };
  }
  return { delivered: true, messageId: decoded.messageId };
}

/**
 * Dispatches SOS notification emails to emergency contacts that have an
 * email address. Returns the number actually delivered.
 */
async function dispatchSosEmailNotifications({ contacts, userName, latitude, longitude, alertId }) {
  if (!isConfigured()) return { notified: 0, total: 0 };

  let list = contacts;
  if (typeof contacts === 'string') {
    try { list = JSON.parse(contacts); } catch (_) { list = null; }
  }
  if (!Array.isArray(list)) return { notified: 0, total: 0 };

  const targets = [];
  for (const c of list) {
    if (!c || typeof c !== 'object') continue;
    if (!isValidEmail(c.email)) continue;
    targets.push({ email: c.email.trim(), name: String(c.name || 'Emergency contact').slice(0, 60) });
  }
  if (!targets.length) return { notified: 0, total: 0 };

  const subject = `SOS ALERT from ${userName || 'SafeSphere'} — assistance needed`;
  const text =
    `EMERGENCY: ${userName || 'A citizen'} triggered an SOS alert via SafeSphere. ` +
    `Location: ${Number(latitude).toFixed(5)}, ${Number(longitude).toFixed(5)}. ` +
    `Alert ID: ${alertId}. Please reach them immediately or dial 112 if unreachable.`;

  const results = await Promise.all(
    targets.map((t) => sendEmail({ to: t.email, subject, text }))
  );
  const notified = results.filter((r) => r.delivered).length;
  return { notified, total: targets.length };
}

module.exports = {
  isConfigured,
  sendEmail,
  dispatchSosEmailNotifications,
  isValidEmail
};
