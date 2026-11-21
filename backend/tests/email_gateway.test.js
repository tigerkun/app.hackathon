/**
 * Email Gateway Test Suite (Brevo — free tier 300 emails/day)
 *
 * Exercises backend/src/services/emailGatewayService.js with a mocked Brevo
 * transport (global.fetch intercept on api.brevo.com):
 * 1. Feature gate: no BREVO_API_KEY → zero network calls
 * 2. sendEmail: correct endpoint, api-key header, sender, recipient, content
 * 3. Invalid recipient email → skipped without network
 * 4. Upstream failure → honest not-delivered
 * 5. SOS email dispatch: contact emails receive the alert; invalid emails skipped
 * 6. Full HTTP flow: authenticated SOS trigger with a contact email → background
 *    email dispatch → emergencyContactsNotified updated with the honest count
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

const bcrypt = require('bcryptjs');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');
const emailGateway = require('../src/services/emailGatewayService');

describe('Email Gateway (Brevo)', () => {
  const REAL_FETCH = global.fetch;
  const SAVED_ENV = { ...process.env };
  let t;
  let brevoCalls = [];
  let brevoFail = false;

  before(async () => {
    process.env.NODE_ENV = 'test';
    process.env.BREVO_API_KEY = 'test-brevo-key';
    process.env.BREVO_SENDER_EMAIL = 'tejasgaur94@gmail.com';
    t = await startTestServer();

    global.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.includes('api.brevo.com')) {
        brevoCalls.push({ url, init: init || {} });
        if (brevoFail) {
          return new Response(JSON.stringify({ message: 'quota exceeded' }), { status: 402 });
        }
        return new Response(
          JSON.stringify({ messageId: '<test-msg-1@smtp-relay.mailin.fr>' }),
          { status: 201 }
        );
      }
      return REAL_FETCH(input, init);
    };
  });

  after(() => {
    global.fetch = REAL_FETCH;
    process.env = SAVED_ENV;
    return t.close();
  });

  it('feature gate: no BREVO_API_KEY → no network calls', async () => {
    process.env.BREVO_API_KEY = '';
    brevoCalls = [];
    const res = await emailGateway.sendEmail({
      to: 'someone@example.com',
      subject: 'test',
      text: 'test'
    });
    assert.equal(res.delivered, false);
    assert.match(res.error, /not configured/);
    assert.equal(brevoCalls.length, 0);
    process.env.BREVO_API_KEY = 'test-brevo-key';
  });

  it('sendEmail: correct endpoint, api-key header, sender and content', async () => {
    brevoCalls = [];
    const res = await emailGateway.sendEmail({
      to: 'contact@example.com',
      subject: 'SOS ALERT test',
      text: 'Emergency at 28.61000, 77.21000'
    });
    assert.equal(res.delivered, true);
    assert.equal(res.messageId, '<test-msg-1@smtp-relay.mailin.fr>');
    assert.equal(brevoCalls.length, 1);
    const call = brevoCalls[0];
    assert.equal(call.url, 'https://api.brevo.com/v3/smtp/email');
    assert.equal(call.init.headers['api-key'], 'test-brevo-key');
    const body = JSON.parse(call.init.body);
    assert.equal(body.sender.email, 'tejasgaur94@gmail.com');
    assert.equal(body.to[0].email, 'contact@example.com');
    assert.equal(body.subject, 'SOS ALERT test');
  });

  it('invalid recipient email → skipped without network', async () => {
    brevoCalls = [];
    const res = await emailGateway.sendEmail({
      to: 'not-an-email',
      subject: 'test',
      text: 'test'
    });
    assert.equal(res.delivered, false);
    assert.equal(brevoCalls.length, 0);
  });

  it('upstream failure → honest not-delivered', async () => {
    brevoFail = true;
    const res = await emailGateway.sendEmail({
      to: 'contact@example.com',
      subject: 'test',
      text: 'test'
    });
    assert.equal(res.delivered, false);
    assert.match(res.error, /HTTP 402/);
    brevoFail = false;
  });

  it('SOS email dispatch: delivers to valid contact emails, skips invalid', async () => {
    brevoCalls = [];
    const contacts = JSON.stringify([
      { name: 'Alpha', phone: '9876543210', email: 'alpha@safesphere.test' },
      { name: 'Beta', phone: '8765432111', email: 'not-an-email' },
      { name: 'Gamma' } // no email at all
    ]);
    const res = await emailGateway.dispatchSosEmailNotifications({
      contacts,
      userName: 'Tejas',
      latitude: 28.61,
      longitude: 77.21,
      alertId: 'sos_test_1'
    });
    assert.equal(res.total, 1, 'only Alpha has a valid email');
    assert.equal(res.notified, 1, 'email delivered counted honestly');
    assert.equal(brevoCalls.length, 1);
    const body = JSON.parse(brevoCalls[0].init.body);
    assert.equal(body.to[0].email, 'alpha@safesphere.test');
    assert.match(body.subject, /SOS ALERT/);
    assert.match(body.textContent, /EMERGENCY: Tejas triggered an SOS alert/);
    assert.match(body.textContent, /112/);
  });

  it('full HTTP flow: SOS with a contact email updates the honest notified count', async () => {
    brevoCalls = [];
    const user = db.saveUser(createUser({
      name: 'Email SOS User',
      email: 'email.sos@safesphere.test',
      phone: '+919876543999',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      emergencyContacts: [
        { name: 'Mail Contact', phone: '9876543211', email: 'mail.contact@safesphere.test' }
      ]
    }));
    const login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'email.sos@safesphere.test', password: 'Str0ngPass!23' }
    });
    assert.equal(login.status, 200);
    const token = login.body.data.accessToken;

    const res = await t.request('/api/v1/sos/trigger', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: { latitude: 28.61, longitude: 77.21 }
    });
    assert.equal(res.status, 201);
    const alertId = res.body.data.id;

    // background dispatch: email delivered → count updated to 1
    let notified = -1;
    for (let i = 0; i < 20; i++) {
      await new Promise(r => setTimeout(r, 100));
      const fresh = db.findAlertById(alertId);
      notified = fresh.emergencyContactsNotified;
      if (notified === 1) break;
    }
    assert.equal(notified, 1, 'email notification counted honestly');
    assert.equal(brevoCalls.length, 1, 'exactly one email dispatch');

    await t.request(`/api/v1/sos/${alertId}/resolve`, { method: 'POST', body: { notes: 'test cleanup' } });
  });
});
