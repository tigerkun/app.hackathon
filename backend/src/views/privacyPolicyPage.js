/**
 * SafeSphere Public Privacy Policy Page
 * Served at GET /privacy and GET /privacy-policy for Google Play Console
 * Data Safety & DPDP Act 2023 transparency compliance.
 */

const privacyPolicyHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SafeSphere — Privacy Policy</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: #0B0F1A;
      color: #E2E8F0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      line-height: 1.65;
      padding: 32px 16px;
    }
    .container {
      max-width: 780px;
      margin: 0 auto;
      background: #111827;
      border: 1px solid rgba(47, 224, 201, 0.25);
      border-radius: 16px;
      padding: 32px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45);
    }
    h1 { color: #2FE0C9; font-size: 26px; margin-bottom: 6px; }
    .meta { color: #94A3B8; font-size: 13px; margin-bottom: 24px; }
    h2 { color: #FFFFFF; font-size: 18px; margin: 22px 0 10px; border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px; }
    p, li { font-size: 14px; color: #CBD5E1; margin-bottom: 8px; }
    ul { padding-left: 20px; margin-bottom: 12px; }
    .notice {
      background: rgba(47, 224, 201, 0.08);
      border: 1px solid rgba(47, 224, 201, 0.35);
      border-radius: 10px;
      padding: 14px 16px;
      margin: 16px 0;
      font-size: 13px;
    }
    a { color: #2FE0C9; }
    code { background: #0B0F1A; padding: 2px 6px; border-radius: 4px; color: #2FE0C9; font-size: 13px; }
  </style>
</head>
<body>
  <main class="container">
    <h1>SafeSphere Privacy Policy</h1>
    <div class="meta">Policy Version 1.0 • Effective Date: November 27, 2026 • Compliance: India Digital Personal Data Protection (DPDP) Act 2023</div>

    <div class="notice">
      <strong>Assistive Safety Notice:</strong> SafeSphere is assistive personal-safety software. It does <strong>not</strong> replace emergency response services (dial <strong>112</strong>, 181, 108, or 101 directly in urgent peril).
    </div>

    <h2>1. Data We Collect &amp; Why</h2>
    <ul>
      <li><strong>Account &amp; Contact Information:</strong> Full name, email address, and mobile phone number used for authentication, one-time verification codes (emailed via Brevo/Resend), and generating your public pseudonymous Safe ID (<code>SF-XXXX-XX</code>).</li>
      <li><strong>Emergency Contacts:</strong> Name, relationship, and phone number of trusted contacts you explicitly enroll to prepare emergency alerts or pre-filled SMS fallback messages.</li>
      <li><strong>Precise Location (GPS):</strong> Collected when you grant location permission to power SOS distress alerts, live guardian trip-sharing sessions (<code>/share</code> &amp; capability links), Trusted Circle live reads you approve, nearby hazard feeds, and safety map distance indicators. Location is <strong>not</strong> tracked silently in the background without an active session or granted permission.</li>
      <li><strong>Community Reports &amp; Safety Markers:</strong> Incident category, description, optional landmark/coordinates, optional photo attachment (≤500 KB), and community verification votes.</li>
      <li><strong>Security Credentials &amp; Optional Anti-Abuse Hash:</strong> Account passwords and security PINs are stored as irreversible bcrypt hashes server-side and encrypted in Android KeyStore / Keychain locally. If you optionally submit the last 4 digits of Aadhaar when filing a report, only a keyed HMAC-SHA256 hash is stored for moderator anti-abuse review — never the full Aadhaar or plaintext digits.</li>
      <li><strong>On-Device Hardware Sensors:</strong> Accelerometer and volume-button events for emergency shake/hold gestures are evaluated strictly on-device and never streamed to servers unless you confirm an SOS broadcast.</li>
      <li><strong>AI Safety Assistant Prompts:</strong> Prompts you send to the AI assistant are transmitted over HTTPS to generate safety guidance without selling personal data.</li>
    </ul>

    <h2>2. Data Sharing &amp; Storage</h2>
    <ul>
      <li><strong>No Advertising or Data Sales:</strong> SafeSphere never sells personal data and shares zero data with advertisers or ad networks.</li>
      <li><strong>Guardians &amp; Trusted Circle:</strong> Live location is visible only to capability-token holders you share a live tracking link with or Trusted Circle connections you explicitly approve (and can revoke instantly in the <em>Who can see me</em> Privacy Hub). Your email and phone are never exposed to other citizens via your Safe ID.</li>
      <li><strong>Encryption &amp; Security:</strong> All network requests to <code>safesphere-backend-c4fs.onrender.com</code> use HTTPS/TLS in transit, capability tracking links set <code>Cache-Control: no-store</code>, and tokens/refresh sessions are revocable.</li>
    </ul>

    <h2>3. Data Retention &amp; Your Right to Erase (DPDP Act 2023)</h2>
    <ul>
      <li><strong>Immediate In-App Account Deletion:</strong> Open the app drawer → <em>Privacy &amp; Consent (DPDP)</em> → <em>Delete My Account</em> (or call authenticated <code>DELETE /api/v1/auth/me</code>) to permanently delete your user account, active sessions, SOS alerts, responder chat messages, live tracking sessions, Trusted Circle connections, beacons, check-ins, and votes.</li>
      <li><strong>Report Expiry:</strong> Community reports auto-expire after 24 hours; deleting your account anonymizes any past report authorship immediately.</li>
    </ul>

    <h2>4. Contact &amp; Grievance Officer</h2>
    <p>For privacy requests, account deletion assistance, or security questions, email <a href="mailto:tejasgaur94@gmail.com">tejasgaur94@gmail.com</a>.</p>
  </main>
</body>
</html>`;

module.exports = {
  privacyPolicyHtml
};
