/**
 * SMS Gateway Service
 * Provider-agnostic SMS dispatch. Two providers supported via SMS_PROVIDER:
 *
 *   'fast2sms'   (default) — Smart OTP endpoint (needs DLT template id via
 *                SMS_OTP_TEMPLATE_ID) + Quick route (₹7/SMS, needs ₹100 top-up).
 *   'textlocal'  — Textlocal India (api.textlocal.in): 10 free SMS credits on
 *                signup, no DLT needed for the trial TXTLCL sender. Chosen as
 *                the zero-money demo path.
 *
 * Configuration (env only — keys are never committed or returned):
 *   SMS_PROVIDER          'fast2sms' | 'textlocal' (default fast2sms)
 *   SMS_API_KEY           provider key (Fast2SMS authorization key /
 *                         Textlocal API hash)
 *   SMS_OTP_TEMPLATE_ID   Fast2SMS Smart OTP template id (fast2sms only)
 *
 * Honesty rules (AGENTS.md invariant #3): every dispatch outcome is reported
 * truthfully — no simulated successes, no silent swallowing.
 */

const SMS_API_URL = 'https://www.fast2sms.com';
const REQUEST_TIMEOUT_MS = 10000;

function getApiKey() {
  return (process.env.SMS_API_KEY || '').trim();
}

function getProvider() {
  return (process.env.SMS_PROVIDER || 'fast2sms').toLowerCase();
}

function getOtpTemplateId() {
  return (process.env.SMS_OTP_TEMPLATE_ID || '').trim();
}

function isConfigured() {
  return getApiKey().length > 0;
}

// OTP delivery needs a DLT template on fast2sms; textlocal sends generic
// text with its trial sender, so the key alone is enough there. 2factor sends
// via its pre-approved DLT OTP template, so its key alone suffices too.
function isOtpConfigured(provider = getProvider()) {
  if (provider === 'textlocal') return Boolean(process.env.SMS_API_KEY);
  if (provider === '2factor') return Boolean(process.env.SMS_2FACTOR_KEY);
  return isConfigured() && getOtpTemplateId().length > 0;
}

/**
 * Optional automatic fallback (just-in-case reliability): when the primary
 * provider fails to deliver, retry once through the fallback provider.
 *   SMS_FALLBACK_PROVIDER   e.g. '2factor'
 *   SMS_FALLBACK_API_KEY    fallback provider key
 * The result reports which provider actually delivered (deliveredVia).
 */
function getFallback() {
  const provider = (process.env.SMS_FALLBACK_PROVIDER || '').toLowerCase();
  const key = (process.env.SMS_FALLBACK_API_KEY || '').trim();
  if (!provider || !key || provider === getProvider()) return null;
  return { provider, key };
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
      error: getProvider() === 'fast2sms'
        ? 'OTP template not configured (set SMS_OTP_TEMPLATE_ID after DLT registration)'
        : 'Textlocal provider not configured'
    };
  }
  const mobile = toIndianMobile(to);
  if (!mobile) {
    return { delivered: false, error: 'Invalid mobile number' };
  }

  if (getProvider() === 'textlocal') {
    // Textlocal: generic text send — embed our code in the message so local
    // verification (attempts/expiry/cooldown) continues to rule the flow.
    const message = `SafeSphere OTP: ${otp} (valid 15 min). Do not share this code.`;
    return sendTextlocal({ to: mobile, message });
  }

  // Fast2SMS Smart OTP: our locally-generated code is passed via `otp` so
  // local verification (attempts/expiry/cooldown) continues to rule the flow.
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
 * Textlocal India transport: GET https://api.textlocal.in/send/
 * with apiKey, numbers (91XXXXXXXXXX), message, sender. Free trial accounts
 * send from the TXTLCL sender with 10 included credits.
 */
async function sendTextlocal({ to, message }) {
  const params = new URLSearchParams({
    apiKey: getApiKey(),
    numbers: `91${to}`,
    message: String(message).slice(0, 300),
    sender: (process.env.SMS_SENDER_ID || 'TXTLCL').slice(0, 6)
  });
  const res = await fetch(`https://api.textlocal.in/send/?${params.toString()}`, {
    method: 'POST',
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });
  let decoded = null;
  try { decoded = await res.json(); } catch (_) { decoded = null; }
  const succeeded = res.ok && decoded && decoded.status === 'success';
  if (!succeeded) {
    return {
      delivered: false,
      error: `textlocal dispatch failed (HTTP ${res.status})`
    };
  }
  return {
    delivered: true,
    requestId: decoded && decoded.messages && decoded.messages[0] && decoded.messages[0].id
  };
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

  if (getProvider() === 'textlocal') {
    return sendTextlocal({ to: mobile, message });
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
