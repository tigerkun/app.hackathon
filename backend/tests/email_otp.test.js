/**
 * Email OTP Service Tests (Resend)
 *
 * Exercises backend/src/services/emailOtpService.js and otpService.js against a
 * mocked Resend transport (global.fetch intercept on api.resend.com):
 * 1. Unconfigured fallback: no RESEND_API_KEY -> zero network calls, non-prod returns devOtp
 * 2. Template & headers: SafeSphere branding, code, 5-min expiry, ignore line, Bearer auth
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
  let brevoCalls = [];
  let resendFail = false;
  let resendThrow = false;
  let resendStatus = 500;
  let brevoFail = false;
  let brevoStatus = 502;

  before(async () => {
    process.env.NODE_ENV = 'test';
    delete process.env.SMS_API_KEY;
    delete process.env.SMS_OTP_TEMPLATE_ID;
    delete process.env.RESEND_API_KEY;
    delete process.env.BREVO_API_KEY;
    t = await startTestServer();

    global.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.includes('api.resend.com/emails')) {
        resendCalls.push({ url, init: init || {} });
        if (resendThrow) {
          throw new Error('ECONNRESET resend socket hangup');
        }
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
      if (url.includes('api.brevo.com/v3/smtp/email')) {
        brevoCalls.push({ url, init: init || {} });
        if (brevoFail) {
          return new Response(
            JSON.stringify({ message: 'brevo upstream error' }),
            { status: brevoStatus }
          );
        }
        return new Response(
          JSON.stringify({ messageId: `<brevo_${brevoCalls.length}@safesphere>` }),
          { status: 201 }
        );
      }
      return REAL_FETCH(input, init);
    };
  });

  beforeEach(() => {
    resendCalls = [];
    brevoCalls = [];
    resendFail = false;
    resendThrow = false;
    resendStatus = 500;
    brevoFail = false;
    brevoStatus = 502;
    delete process.env.RESEND_API_KEY;
    delete process.env.BREVO_API_KEY;
    delete process.env.BREVO_SENDER_EMAIL;
    delete process.env.OTP_FROM_EMAIL;
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

  it('builds SafeSphere email template with 5-min expiry matching config.otpExpirySeconds and ignore notice', () => {
    assert.equal(config.otpExpirySeconds, 300);
    const content = emailOtpService.buildOtpEmailContent({ otp: '654321' });
    assert.match(content.subject, /SafeSphere/i);
    assert.match(content.text, /Your verification code is 654321/);
    assert.match(content.text, /5 minutes/i);
    assert.doesNotMatch(content.text, /10 minutes/i);
    assert.match(content.text, /ignore this email/i);
    assert.match(content.html, /SafeSphere/);
    assert.match(content.html, /654321/);
    assert.match(content.html, /5 minutes/i);
    assert.doesNotMatch(content.html, /10 minutes/i);
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

  it('uses Brevo transport cleanly when RESEND_API_KEY is absent and BREVO_API_KEY + BREVO_SENDER_EMAIL are set', async () => {
    process.env.BREVO_API_KEY = 'xkeysib-test-secret';
    process.env.BREVO_SENDER_EMAIL = 'noreply@safesphere.app';

    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100025', email: 'brevo.citizen@example.com' }
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.emailDispatched, true);
    assert.equal(res.body.channel, 'email');
    assert.equal(res.body.devOtp, undefined);
    assert.equal(resendCalls.length, 0);
    assert.equal(brevoCalls.length, 1);
    assert.equal(brevoCalls[0].init.headers['api-key'], 'xkeysib-test-secret');
    const body = JSON.parse(brevoCalls[0].init.body);
    assert.equal(body.sender.email, 'noreply@safesphere.app');
    assert.deepEqual(body.to, [{ email: 'brevo.citizen@example.com' }]);
    assert.match(body.textContent, /Your verification code is \d{6}/);
  });

  it('fails over from Resend HTTP 503 to Brevo at runtime and increments daily quota only once', async () => {
    process.env.RESEND_API_KEY = 're_failover_secret_1';
    process.env.BREVO_API_KEY = 'xkeysib-failover-secret-2';
    process.env.BREVO_SENDER_EMAIL = 'noreply@safesphere.app';
    resendFail = true;
    resendStatus = 503;

    const targetEmail = 'failover.http@example.com';
    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100026', email: targetEmail }
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.emailDispatched, true);
    assert.equal(res.body.channel, 'email');
    assert.equal(res.body.devOtp, undefined);
    assert.equal(resendCalls.length, 1);
    assert.equal(brevoCalls.length, 1);
    const day = new Date().toISOString().slice(0, 10);
    assert.equal(db.getEmailOtpCount(targetEmail, day), 1, 'failover must not double-count daily quota');
    assert.doesNotMatch(JSON.stringify(res.body), /re_failover_secret_1|xkeysib-failover-secret-2/);
  });

  it('fails over from Resend network rejection to Brevo at runtime', async () => {
    process.env.RESEND_API_KEY = 're_failover_secret_3';
    process.env.BREVO_API_KEY = 'xkeysib-failover-secret-4';
    process.env.BREVO_SENDER_EMAIL = 'noreply@safesphere.app';
    resendThrow = true;

    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100027', email: 'failover.net@example.com' }
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.emailDispatched, true);
    assert.equal(res.body.channel, 'email');
    assert.equal(resendCalls.length, 1);
    assert.equal(brevoCalls.length, 1);
  });

  it('does not forward onboarding@resend.dev to Brevo when BREVO_SENDER_EMAIL is unset', async () => {
    process.env.RESEND_API_KEY = 're_sandbox_only';
    process.env.OTP_FROM_EMAIL = 'SafeSphere <onboarding@resend.dev>';
    process.env.BREVO_API_KEY = 'xkeysib-no-sender';
    resendFail = true;
    resendStatus = 403;

    assert.deepEqual(emailOtpService.getConfiguredProviders(), ['resend']);
    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone: '+919811100028', email: 'sandbox.guard@example.com' }
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.emailDispatched, false);
    assert.equal(res.body.channel, 'dev_fallback');
    assert.equal(resendCalls.length, 1);
    assert.equal(brevoCalls.length, 0);
  });

  it('returns 502 OTP_DISPATCH_FAILED in production when both Resend and Brevo fail, deleting OTP and leaking no keys', async () => {
    process.env.RESEND_API_KEY = 're_both_fail_key';
    process.env.BREVO_API_KEY = 'xkeysib-both-fail-key';
    process.env.BREVO_SENDER_EMAIL = 'noreply@safesphere.app';
    config.isProduction = true;
    config.isDev = false;
    config.isTest = false;
    resendFail = true;
    resendStatus = 502;
    brevoFail = true;
    brevoStatus = 503;

    const phone = '+919811100029';
    const res = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone, email: 'both.fail@example.com' }
    });

    assert.equal(res.status, 502);
    assert.equal(res.body.success, false);
    assert.equal(res.body.error.code, 'OTP_DISPATCH_FAILED');
    assert.equal(res.body.devOtp, undefined);
    assert.equal(db.getOtp('919811100029'), null, 'OTP must be deleted when prod dispatch fails');
    assert.equal(resendCalls.length, 1);
    assert.equal(brevoCalls.length, 1);
    assert.doesNotMatch(JSON.stringify(res.body), /re_both_fail_key|xkeysib-both-fail-key/);
  });

  it('enforces OTP purpose isolation across /pin/reset and /otp/verify without purpose-oracle leak', async () => {
    const phone = '+919811100030';
    const email = 'purpose.isolation@example.com';
    db.saveUser(createUser({
      name: 'Purpose Guard User',
      email,
      phone,
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      pin: bcrypt.hashSync('1234', 8),
      pinHash: bcrypt.hashSync('1234', 8)
    }));

    // 1. Issue a login OTP
    const loginSend = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone, purpose: 'login' }
    });
    assert.equal(loginSend.status, 200);
    const loginOtp = loginSend.body.devOtp;
    assert.match(loginOtp, /^\d{6}$/);

    // Wrong code on /pin/reset must return 401 INVALID_OTP (no purpose oracle leak)
    const wrongCodeReset = await t.request('/api/v1/auth/pin/reset', {
      method: 'POST',
      body: { phone, otp: '000000', newPin: '9999' }
    });
    assert.equal(wrongCodeReset.status, 401);
    assert.equal(wrongCodeReset.body.error.code, 'INVALID_OTP');

    // Correct code issued for 'login' must be rejected on /pin/reset with 400 OTP_PURPOSE_MISMATCH
    const crossReset = await t.request('/api/v1/auth/pin/reset', {
      method: 'POST',
      body: { phone, otp: loginOtp, newPin: '9999' }
    });
    assert.equal(crossReset.status, 400);
    assert.equal(crossReset.body.error.code, 'OTP_PURPOSE_MISMATCH');

    // Original login OTP remains valid for /otp/verify (with omitted purpose or 'verification')
    const verifyOk = await t.request('/api/v1/auth/otp/verify', {
      method: 'POST',
      body: { phone, otp: loginOtp }
    });
    assert.equal(verifyOk.status, 200);
    assert.equal(verifyOk.body.verified, true);

    // 2. Issue a 'verification' OTP (directly replacing cooldown in store) -> also rejected on /pin/reset
    db.deleteOtp('919811100030');
    const verSend = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone, purpose: 'verification' }
    });
    assert.equal(verSend.status, 200);
    const verOtp = verSend.body.devOtp;

    const verCrossReset = await t.request('/api/v1/auth/pin/reset', {
      method: 'POST',
      body: { phone, otp: verOtp, newPin: '8888' }
    });
    assert.equal(verCrossReset.status, 400);
    assert.equal(verCrossReset.body.error.code, 'OTP_PURPOSE_MISMATCH');

    // 'verification' OTP works on /otp/verify
    const verVerifyOk = await t.request('/api/v1/auth/otp/verify', {
      method: 'POST',
      body: { phone, otp: verOtp, purpose: 'verification' }
    });
    assert.equal(verVerifyOk.status, 200);

    // 3. Issue a 'pin_reset' OTP -> rejected on /otp/verify (even if body passes purpose: 'pin_reset')
    db.deleteOtp('919811100030');
    const resetSend = await t.request('/api/v1/auth/otp/send', {
      method: 'POST',
      body: { phone, purpose: 'pin_reset' }
    });
    assert.equal(resetSend.status, 200);
    const resetOtp = resetSend.body.devOtp;

    const crossVerify1 = await t.request('/api/v1/auth/otp/verify', {
      method: 'POST',
      body: { phone, otp: resetOtp }
    });
    assert.equal(crossVerify1.status, 400);
    assert.equal(crossVerify1.body.error.code, 'OTP_PURPOSE_MISMATCH');

    const crossVerify2 = await t.request('/api/v1/auth/otp/verify', {
      method: 'POST',
      body: { phone, otp: resetOtp, purpose: 'pin_reset' }
    });
    assert.equal(crossVerify2.status, 400);
    assert.equal(crossVerify2.body.error.code, 'OTP_PURPOSE_MISMATCH');

    // Finally works on /pin/reset
    const resetOk = await t.request('/api/v1/auth/pin/reset', {
      method: 'POST',
      body: { phone, otp: resetOtp, newPin: '7777' }
    });
    assert.equal(resetOk.status, 200);
    assert.equal(resetOk.body.success, true);
  });
});
