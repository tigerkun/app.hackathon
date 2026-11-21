/**
 * Privacy Hub Test Suite (M5)
 *
 * GET /api/v1/location/sessions/mine — "Who can see me" backend:
 * 1. Requires auth (401 without token)
 * 2. Returns only the caller's own active tracking sessions
 * 3. NEVER leaks the raw tracking token in list responses
 * 4. Returns empty list (not error) when the user has no sessions
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

const bcrypt = require('bcryptjs');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');

async function loginAs(t, email) {
  const res = await t.request('/api/v1/auth/login', {
    method: 'POST',
    body: { emailOrPhone: email, password: 'Str0ngPass!23' }
  });
  assert.equal(res.status, 200);
  return res.body.data.accessToken;
}

describe('Privacy Hub — sessions/mine (M5)', () => {
  let t;
  let aliceToken;
  let bobToken;

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();

    db.saveUser(createUser({
      id: 'usr_m5_alice',
      name: 'M5 Alice',
      email: 'm5.alice@safesphere.test',
      phone: '+918800500001',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    db.saveUser(createUser({
      id: 'usr_m5_bob',
      name: 'M5 Bob',
      email: 'm5.bob@safesphere.test',
      phone: '+918800500002',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));

    aliceToken = await loginAs(t, 'm5.alice@safesphere.test');
    bobToken = await loginAs(t, 'm5.bob@safesphere.test');
  });

  after(async () => t.close());

  it('requires auth → 401 without token', async () => {
    const res = await t.request('/api/v1/location/sessions/mine');
    assert.equal(res.status, 401);
  });

  it('returns empty list for a user with no sessions (honest, not error)', async () => {
    const res = await t.request('/api/v1/location/sessions/mine', {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.deepEqual(res.body.data.activeSessions, []);
    assert.equal(res.body.data.count, 0);
  });

  it('lists only the caller\'s own active sessions and NEVER leaks the token', async () => {
    // Alice creates a live tracking session (guest allowed via optionalAuth)
    const share = await t.request('/api/v1/location/share-session', {
      method: 'POST',
      headers: { Authorization: `Bearer ${aliceToken}` },
      body: { latitude: 28.6139, longitude: 77.209, durationMinutes: 30 }
    });
    assert.equal(share.status, 201, `share-session → ${JSON.stringify(share.body)}`);
    assert.ok(share.body.data.shareUrl, 'share-session returns a share link');

    // Bob's list stays empty (ownership isolation)
    const bobList = await t.request('/api/v1/location/sessions/mine', {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(bobList.status, 200);
    assert.equal(bobList.body.data.count, 0);

    // Alice sees her session — with token and any credential material scrubbed
    const aliceList = await t.request('/api/v1/location/sessions/mine', {
      headers: { Authorization: `Bearer ${aliceToken}` }
    });
    assert.equal(aliceList.status, 200);
    assert.equal(aliceList.body.data.count, 1);
    const session = aliceList.body.data.activeSessions[0];
    assert.ok(session.id);
    assert.equal(session.status, 'active');
    assert.equal(session.token, undefined, 'tracking token must be scrubbed from mine list');
    assert.equal(session.breadcrumbs, undefined, 'bulk breadcrumb payload must not be returned');
    assert.ok(typeof session.breadcrumbCount === 'number', 'breadcrumb COUNT is fine');
  });

  it('expired sessions drop out of the active list', async () => {
    // Create and immediately expire a session for Bob
    const share = await t.request('/api/v1/location/share-session', {
      method: 'POST',
      headers: { Authorization: `Bearer ${bobToken}` },
      body: { latitude: 19.076, longitude: 72.8777, durationMinutes: 30 }
    });
    assert.equal(share.status, 201);
    const sessionId = share.body.data.sessionId;

    const term = await t.request(`/api/v1/location/terminate/${sessionId}`, {
      method: 'POST',
      body: { token: share.body.data.token, reason: 'privacy-hub-test' }
    });
    assert.equal(term.status, 200, `terminate → ${JSON.stringify(term.body)}`);

    const list = await t.request('/api/v1/location/sessions/mine', {
      headers: { Authorization: `Bearer ${bobToken}` }
    });
    assert.equal(list.body.data.count, 0, 'terminated session must not appear in active list');
  });
});
