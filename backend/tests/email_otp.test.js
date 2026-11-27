/**
 * Email OTP Service Tests (Resend)
 *
 * Exercises backend/src/services/emailOtpService.js and otpService.js against a
 * mocked Resend transport (global.fetch intercept on api.resend.com):
 * 1. Unconfigured fallback: no RESEND_API_KEY -> zero network calls, non-prod returns devOtp
 * 2. Template & headers: SafeSphere branding, code, 10-min expiry, ignore line, Bearer auth
 * 3. Full HTTP success path: emails code, returns channel='email', omits devOtp even in test/prod
 * 4. Verification + Forgot-PIN reset works end-to-end with emailed OTP
 * 5. Provider-down fallback: non-prod returns devOtp honestly; prod throws 502 without leaking OTP
 * 6. Production response never leaks OTP code on success or failure
 * 7. Per-email daily cap (5/day) blocks 6th attempt with 429 EMAIL_OTP_DAILY_LIMIT
 * 8. Account deletion cleans up email_otp_limits row
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const config = require('../src/config');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');
const emailOtpService = require('../src/services/emailOtpService');

describe('Email OTP Service (Resend)', () => {
  const REAL_FETCH = global.fetch;
  const SAVED_ENV = { ...process.env };
  const SAVED_CONFIG = {
    isProduction: config.isProduction,
    isDev: config.isDev,
    isTest: config.isTest
  };

  let t;
  let resendCalls = [];
  let resendFail = false;
  let resendStatus = 500;

  before(async () => {
    process.env.NODE_ENV = 'test';
    delete process.env.SMS_API_KEY;
    delete process.env.SMS_OTP_TEMPLATE_ID;
    t = await startTestServer();

    global.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.includes('api.resend.com/emails')) {
        resendCalls.push({ url, init: init || {} });
        if (resendFail) {
          return new Response(
            JSON.stringify({ message: 'upstream error' }),
            { status: resendStatus }
          );
        }
        return new Response(
          JSON.stringify({ id: `re_msg_${resendCalls.length}` }),
          { status: 200 }
        );
      }
      return REAL_FETCH(input, init);
    };
  });

  beforeEach(() => {
    resendCalls = [];
    resendFail = false;
    resendStatus = 500;
    config.isProduction = SAVED_CONFIG.isProduction;
    config.isDev = SAVED_CONFIG.isDev;
    config.isTest = SAVED_CONFIG.isTest;
  });

  after(() => {
    global.fetch = REAL_FETCH;
    process.env = SAVED_ENV;
    config.isProduction = SAVED_CONFIG.isProduction;
    config.isDev = SAVED_CONFIG.isDev;
    config.isTest = SAVED_CONFIG.isTest;
    return t.close();
  });

  it('skips Resend calls when RESEND_API_KEY is unset and surfaces devOtp in test mode', async () => {
    delete process.env.RESEND_API_KEY;
    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100001', email: 'unconfigured@example.com' }
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.emailDispatched, false);
    assert.equal(res.body.channel, 'dev_fallback');
    assert.match(res.body.devOtp, /^\d{6}$/);
    assert.equal(resendCalls.length, 0);
  });

  it('builds SafeSphere email template with 10-min expiry and ignore notice', () => {
    const content = emailOtpService.buildOtpEmailContent({ otp: '654321' });
    assert.match(content.subject, /SafeSphere/i);
    assert.match(content.text, /Your verification code is 654321/);
    assert.match(content.text, /10 minutes/i);
    assert.match(content.text, /ignore this email/i);
    assert.match(content.html, /SafeSphere/);
    assert.match(content.html, /654321/);
    assert.match(content.html, /10 minutes/i);
  });

  it('full HTTP success path emails OTP via Resend, omits devOtp, and verifies OTP + PIN reset', async () => {
    process.env.RESEND_API_KEY = 're_test_secret_key_123';
    process.env.OTP_FROM_EMAIL = 'otp@safesphere.app';

    const phone = '+919811100002';
    const email = 'alice.otp@example.com';
    db.saveUser(createUser({
      name: 'Alice Email OTP',
      email,
      phone,
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      pin: bcrypt.hashSync('1234', 8),
      pinHash: bcrypt.hashSync('1234', 8)
    }));

    const sendRes = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone, purpose: 'pin_reset' }
    });

    assert.equal(sendRes.status, 200);
    assert.equal(sendRes.body.success, true);
    assert.equal(sendRes.body.emailDispatched, true);
    assert.equal(sendRes.body.channel, 'email');
    assert.equal(sendRes.body.maskedEmail, 'al***@example.com');
    assert.match(sendRes.body.message, /emailed to al\*\*\*@example\.com/i);
    assert.equal(sendRes.body.devOtp, undefined, 'devOtp must be omitted when provider delivered email');
    assert.equal(sendRes.body.data.devOtp, undefined);

    assert.equal(resendCalls.length, 1);
    const call = resendCalls[0];
    assert.equal(call.url, 'https://api.resend.com/emails');
    assert.equal(call.init.headers.Authorization, 'Bearer re_test_secret_key_123');
    const payload = JSON.parse(call.init.body);
    assert.equal(payload.from, 'otp@safesphere.app');
    assert.deepEqual(payload.to, [email]);
    const codeMatch = payload.text.match(/Your verification code is (\d{6})/);
    assert.ok(codeMatch, 'email text must carry the 6-digit code');
    const emailedCode = codeMatch[1];

    // Consuming via forgot-PIN endpoint works with the emailed code.
    const resetRes = await t.request('/api/v1/auth/pin/reset', {
      method: 'POST',
      body: { phone, otp: emailedCode, newPin: '5678' }
    });
    assert.equal(resetRes.status, 200);
    assert.equal(resetRes.body.success, true);
  });

  it('provider-down in non-prod falls back honestly to devOtp', async () => {
    process.env.RESEND_API_KEY = 're_test_secret_key_123';
    resendFail = true;
    resendStatus = 503;

    const sendRes = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100003', email: 'fallback.nonprod@example.com' }
    });

    assert.equal(sendRes.status, 200);
    assert.equal(sendRes.body.emailDispatched, false);
    assert.equal(sendRes.body.channel, 'dev_fallback');
    assert.doesNotMatch(sendRes.body.message, /^Verification code emailed/i);
    assert.match(sendRes.body.devOtp, /^\d{6}$/);
  });

  it('production never leaks OTP code on success and returns 502 OTP_DISPATCH_FAILED on provider outage', async () => {
    process.env.RESEND_API_KEY = 're_test_secret_key_123';
    config.isProduction = true;
    config.isDev = false;
    config.isTest = false;

    const okRes = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100004', email: 'prod.ok@example.com' }
    });
    assert.equal(okRes.status, 200);
    assert.equal(okRes.body.emailDispatched, true);
    assert.equal(okRes.body.devOtp, undefined);
    assert.equal(okRes.body.data.devOtp, undefined);
    assert.doesNotMatch(JSON.stringify(okRes.body), /re_test_secret_key_123/);

    resendFail = true;
    resendStatus = 502;
    const failRes = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100005', email: 'prod.fail@example.com' }
    });
    assert.equal(failRes.status, 502);
    assert.equal(failRes.body.success, false);
    assert.equal(failRes.body.error.code, 'OTP_DISPATCH_FAILED');
    assert.equal(failRes.body.devOtp, undefined);
    assert.doesNotMatch(JSON.stringify(failRes.body), /re_test_secret_key_123/);
  });

  it('enforces per-email daily cap (5/day) and cleans up counter on user deletion', async () => {
    process.env.RESEND_API_KEY = 're_test_secret_key_123';
    const targetEmail = 'capped.user@example.com';

    // Create user so deleteUser cascade can be checked afterwards.
    const user = db.saveUser(createUser({
      name: 'Capped User',
      email: targetEmail,
      phone: '+919811100010',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));

    for (let i = 0; i < 5; i++) {
      const res = await t.request('/api/v1/auth/otp/send', {
        method: 'POST',
        body: { phone: `+91981110001${i}`, email: targetEmail }
      });
      assert.equal(res.status, 200, `attempt ${i + 1} should succeed`);
    }

    const sixth = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100019', email: targetEmail }
    });
    assert.equal(sixth.status, 429);
    assert.equal(sixth.body.error.code, 'EMAIL_OTP_DAILY_LIMIT');

    const day = new Date().toISOString().slice(0, 10);
    assert.equal(db.getEmailOtpCount(targetEmail, day), 5);
    assert.equal(db.deleteUser(user.id), true);
    assert.equal(db.getEmailOtpCount(targetEmail, day), 0);
  });
});
