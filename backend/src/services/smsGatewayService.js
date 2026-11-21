/**
 * SMS Gateway Service
 * Provider: Fast2SMS (India) — chosen after MSG91's login pipeline proved
 * broken. Designed provider-agnostic: swap the transport below without
 * touching callers (otpService, sosService).
 *
 * Configuration (env only — the key is never committed or returned):
 *   SMS_API_KEY            Fast2SMS authorization key (required to enable)
 *   SMS_OTP_TEMPLATE_ID    Fast2SMS Smart OTP template id (required for OTP
 *                          delivery — created in Dashboard → Smart OTP after
 *                          DLT entity/sender/content registration)
 *
 * Routes used (per docs.fast2sms.com):
 *   OTP delivery  → POST /dev/otp/send — Smart OTP with a DLT-registered
 *                   template; passes OUR locally-generated code via the `otp`
 *                   field so local verification (attempts/expiry) still rules.
 *                   Requires DLT registration + SMS_OTP_TEMPLATE_ID.
 *   Free-text SMS → POST /dev/bulkV2 (route: 'q') — Quick route, ₹7.0000 per
 *                   SMS, no DLT needed, but requires a one-time transaction of
 *                   ₹100+ on the account. Used for SOS emergency-contact
 *                   dispatch; callers decide whether the cost is acceptable.
 *
 * Honesty rules (AGENTS.md invariant #3): every dispatch outcome is reported
 * truthfully — no simulated successes, no silent swallowing.
 */

const SMS_API_URL = 'https://www.fast2sms.com';
const REQUEST_TIMEOUT_MS = 10000;

function getApiKey() {
  return (process.env.SMS_API_KEY || '').trim();
}

function getOtpTemplateId() {
  return (process.env.SMS_OTP_TEMPLATE_ID || '').trim();
}

function isConfigured() {
  return getApiKey().length > 0;
}

function isOtpConfigured() {
  return getApiKey().length > 0 && getOtpTemplateId().length > 0;
}

/**
 * Normalizes Indian mobile numbers to the 10-digit form Fast2SMS expects.
 * Accepts '+919876543210', '919876543210', '09876543210', '9876543210'.
 * Returns null when the number is not a plausible Indian mobile.
 */
function toIndianMobile(rawPhone) {
  if (!rawPhone) return null;
  let digits = String(rawPhone).replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  if (digits.length !== 10 || !/^[6-9]/.test(digits)) return null;
  return digits;
}

async function post(path, body) {
  const res = await fetch(`${SMS_API_URL}${path}`, {
    method: 'POST',
    headers: {
      authorization: getApiKey(),
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });
  let decoded = null;
  try { decoded = await res.json(); } catch (_) { decoded = null; }
  return { ok: res.ok, status: res.status, decoded };
}

/**
 * Sends a login/verification OTP through Fast2SMS's pre-approved OTP route.
 * @returns {Promise<{delivered: boolean, requestId?: string, error?: string}>}
 */
async function sendOtpSms({ to, otp }) {
  if (!isConfigured()) {
    return { delivered: false, error: 'SMS gateway not configured' };
  }
  if (!isOtpConfigured()) {
    return {
      delivered: false,
      error: 'OTP template not configured (set SMS_OTP_TEMPLATE_ID after DLT registration)'
    };
  }
  const mobile = toIndianMobile(to);
  if (!mobile) {
    return { delivered: false, error: 'Invalid mobile number' };
  }

  // Our locally-generated code is passed via `otp` so local verification
  // (attempts/expiry/cooldown) continues to rule the login flow.
  const { ok, status, decoded } = await post('/dev/otp/send', {
    mobile,
    otp_id: getOtpTemplateId(),
    otp: String(otp),
    otp_expiry: 15
  });

  const succeeded = ok && decoded && (decoded.return === true || decoded.status_code === 200);
  if (!succeeded) {
    // Fast2SMS error bodies carry { status_code, message } — log status only,
    // message text may echo account metadata.
    return {
      delivered: false,
      error: `fast2sms otp dispatch failed (HTTP ${status})`
    };
  }
  return { delivered: true, requestId: decoded && (decoded.request_id || decoded.requestId) };
}

/**
 * Sends a free-text SMS via the Quick route (no DLT template needed;
 * ₹7.0000 per SMS). Used for SOS emergency-contact notifications.
 * @returns {Promise<{delivered: boolean, requestId?: string, error?: string}>}
 */
async function sendQuickSms({ to, message }) {
  if (!isConfigured()) {
    return { delivered: false, error: 'SMS gateway not configured' };
  }
  const mobile = toIndianMobile(to);
  if (!mobile) {
    return { delivered: false, error: 'Invalid mobile number' };
  }

  const { ok, status, decoded } = await post('/dev/bulkV2', {
    route: 'q',
    message: String(message).slice(0, 300),
    numbers: mobile
  });

  const succeeded = ok && decoded && decoded.return === true;
  if (!succeeded) {
    return {
      delivered: false,
      error: `fast2sms quick dispatch failed (HTTP ${status})`
    };
  }
  return { delivered: true, requestId: decoded && decoded.request_id };
}

/**
 * Parses a user's emergencyContacts JSON column into [{ name, phone }, ...].
 * Entries without a plausible Indian mobile are skipped.
 */
function parseEmergencyContacts(rawContacts) {
  if (!rawContacts) return [];
  let list = rawContacts;
  if (typeof rawContacts === 'string') {
    try { list = JSON.parse(rawContacts); } catch (_) { return []; }
  }
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const contact of list) {
    if (!contact || typeof contact !== 'object') continue;
    const phone = toIndianMobile(contact.phone);
    if (!phone) continue;
    out.push({ name: String(contact.name || 'Emergency contact').slice(0, 60), phone });
  }
  return out;
}

/**
 * Dispatches an SOS notification SMS to every emergency contact.
 * Returns the number of contacts actually delivered (honest count).
 */
async function dispatchSosNotifications({ contacts, userName, latitude, longitude, alertId }) {
  const targets = parseEmergencyContacts(contacts);
  if (!targets.length) return { notified: 0, total: 0 };

  const message =
    `SOS ALERT: ${userName || 'A citizen'} triggered an emergency SOS via SafeSphere. ` +
    `Location: ${Number(latitude).toFixed(5)}, ${Number(longitude).toFixed(5)}. ` +
    `Alert: ${alertId}. Call them back or dial 112 if unreachable.`;

  const results = await Promise.all(
    targets.map((c) => sendQuickSms({ to: c.phone, message }))
  );
  const notified = results.filter((r) => r.delivered).length;
  return { notified, total: targets.length };
}

module.exports = {
  isConfigured,
  isOtpConfigured,
  sendOtpSms,
  sendQuickSms,
  dispatchSosNotifications,
  parseEmergencyContacts,
  toIndianMobile
};
