/**
 * Audit-Fix Regression Suite
 *
 * Covers bugs found in the post-M6 line-by-line audit:
 * 1. SOS clientRequestId idempotency — an offline-queue replay after a lost
 *    response must return the ORIGINAL alert, never a duplicate row, and the
 *    replayed response must carry a working resolve credential.
 * 2. Guest share-session identity stripping — a guest must never assert a
 *    userId (privacy-hub attribution forgery / victim-name resolution).
 * 3. Connection peer projection — pending/active connection payloads must
 *    never leak email, phone, emergency contacts, strikes, or ban status.
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
  assert.equal(res.status, 200, `login ${email} → ${res.status}`);
  return res.body.data.accessToken;
}

describe('Audit fixes — SOS idempotency, guest identity, peer projection', () => {
  let t;

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();

    db.saveUser(createUser({
      id: 'usr_audit_owner',
      name: 'Audit Owner',
      email: 'audit.owner@safesphere.test',
      phone: '+918800400001',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    db.saveUser(createUser({
      id: 'usr_audit_peer',
      name: 'Audit Peer',
      email: 'audit.peer@safesphere.test',
      phone: '+918800400002',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
  });

  after(async () => {
    if (t) await t.close();
  });

  it('SOS replay with same clientRequestId returns original alert, no duplicate', async () => {
    const key = `audit_idem_${Date.now()}`;
    const payload = {
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 12,
      clientRequestId: key
    };

    const first = await t.request('/api/v1/sos/trigger', { method: 'POST', body: payload });
    assert.equal(first.status, 201, JSON.stringify(first.body));
    const alertId = first.body.data.id || first.body.id;
    assert.ok(first.body.resolveToken || first.body.data.resolveToken, 'first response carries resolveToken');

    // Simulate the lost-response replay: identical clientRequestId.
    const replay = await t.request('/api/v1/sos/trigger', { method: 'POST', body: payload });
    assert.equal(replay.status, 200, JSON.stringify(replay.body));
    assert.equal(replay.body.deduplicated, true);
    const replayId = replay.body.data.id || replay.body.id;
    assert.equal(replayId, alertId, 'replay must return the SAME alert id');

    // Exactly one alert row exists for this request key.
    const matches = db.getAllAlerts().filter((a) => a.clientRequestId === key);
    assert.equal(matches.length, 1, 'idempotency key must not create a second alert');

    // The replayed response's rotated resolveToken must actually resolve.
    const resolveToken = replay.body.resolveToken || replay.body.data.resolveToken;
    assert.ok(resolveToken, 'replay must carry a working resolveToken');
    const resolved = await t.request('/api/v1/sos/resolve', {
      method: 'POST',
      body: { id: alertId, resolveToken, notes: 'audit test resolve' }
    });
    assert.equal(resolved.status, 200, JSON.stringify(resolved.body));
  });

  it('SOS without clientRequestId still works (backward compatible)', async () => {
    const res = await t.request('/api/v1/sos/trigger', {
      method: 'POST',
      body: { latitude: 13.0, longitude: 77.6, accuracy: 20 }
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.ok(res.body.data.id || res.body.id);
  });

  it('SOS idempotency key cannot replay another user’s alert', async () => {
    const ownerToken = await loginAs(t, 'audit.owner@safesphere.test');
    const peerToken = await loginAs(t, 'audit.peer@safesphere.test');
    const payload = {
      latitude: 12.9716,
      longitude: 77.5946,
      clientRequestId: `audit_scoped_${Date.now()}`
    };
    const original = await t.request('/api/v1/sos/trigger', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ownerToken}` },
      body: payload
    });
    assert.equal(original.status, 201, JSON.stringify(original.body));
    const originalId = original.body.data.id;
    const originalHash = db.findAlertById(originalId).resolveTokenHash;

    const otherUser = await t.request('/api/v1/sos/trigger', {
      method: 'POST',
      headers: { Authorization: `Bearer ${peerToken}` },
      body: payload
    });
    assert.equal(otherUser.status, 201, JSON.stringify(otherUser.body));
    assert.notEqual(otherUser.body.data.id, originalId);
    assert.equal(db.findAlertById(originalId).resolveTokenHash, originalHash);
  });

  it('guest share-session ignores a forged body.userId', async () => {
    const res = await t.request('/api/v1/location/share-session', {
      method: 'POST',
      body: {
        latitude: 12.9,
        longitude: 77.5,
        userId: 'usr_audit_owner', // forged attribution attempt
        userName: 'Audit Owner'
      }
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const sessionId = res.body.data.sessionId || res.body.sessionId;
    const session = db.findTrackingSessionById(sessionId);
    assert.ok(session, 'session persisted');
    assert.equal(session.userId, null, 'guest session must not be attributed to a real user');
    // Clean up so later tests see an empty active-session list.
    db.updateTrackingSession(sessionId, { status: 'ended', endedAt: new Date().toISOString() });
  });

  it('unverified phone cannot report or vote; verified phone can', async () => {
    const email = `audit.unverified.${Date.now()}@safesphere.test`;
    const reg = await t.request('/api/v1/auth/register', {
      method: 'POST',
      body: {
        name: 'Audit Unverified',
        email,
        phone: '+91 9888899999',
        password: 'Str0ngPass!23'
      }
    });
    assert.equal(reg.status, 201, JSON.stringify(reg.body));
    const token = reg.body.data.accessToken;
    const userId = reg.body.data.user.id;

    const report = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: { type: 'Theft', description: 'audit gate test', location: 'Test Nagar' }
    });
    assert.equal(report.status, 403, JSON.stringify(report.body));
    assert.equal(report.body.error.code, 'PHONE_NOT_VERIFIED');

    // Simulate OTP verification completing.
    db.updateUser(userId, { phoneVerified: true });

    const report2 = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: { type: 'Theft', description: 'audit gate test 2', location: 'Test Nagar' }
    });
    assert.equal(report2.status, 201, JSON.stringify(report2.body));
    const reportId = report2.body.data.id || report2.body.report.id;

    // Self-vote on own report is rejected.
    const selfVote = await t.request(`/api/v1/reports/${reportId}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: { vote: 'confirm' }
    });
    assert.equal(selfVote.status, 403, JSON.stringify(selfVote.body));
    assert.equal(selfVote.body.error.code, 'CANNOT_VOTE_OWN_REPORT');

    // A different verified user CAN vote.
    const email2 = `audit.verified.${Date.now()}@safesphere.test`;
    const reg2 = await t.request('/api/v1/auth/register', {
      method: 'POST',
      body: { name: 'Audit Verified', email: email2, phone: '+91 9888877777', password: 'Str0ngPass!23' }
    });
    const token2 = reg2.body.data.accessToken;
    const userId2 = reg2.body.data.user.id;
    db.updateUser(userId2, { phoneVerified: true });
    const vote = await t.request(`/api/v1/reports/${reportId}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token2}` },
      body: { vote: 'confirm' }
    });
    assert.equal(vote.status, 200, JSON.stringify(vote.body));
  });

  it('report verdict effects are not repeatable (idempotent strikes/reputation)', async () => {
    // Admin verdicts twice on the same report must apply reputation/strike
    // effects exactly once.
    const admin = db.findUserById('usr_audit_owner');
    void admin;
    const modEmail = `audit.mod.${Date.now()}@safesphere.test`;
    db.saveUser(createUser({
      id: `usr_audit_mod_${Date.now()}`,
      name: 'Audit Mod',
      email: modEmail,
      phone: '+91 9777788888',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'admin',
      phoneVerified: true
    }));
    const modToken = await loginAs(t, modEmail);

    // Reporter (verified)
    const repEmail = `audit.rep.${Date.now()}@safesphere.test`;
    const repReg = await t.request('/api/v1/auth/register', {
      method: 'POST',
      body: { name: 'Audit Rep', email: repEmail, phone: '+91 9666677777', password: 'Str0ngPass!23' }
    });
    const repToken = repReg.body.data.accessToken;
    const repId = repReg.body.data.user.id;
    db.updateUser(repId, { phoneVerified: true });

    const rep = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${repToken}` },
      body: { type: 'Theft', description: 'verdict idem', location: 'Test Nagar' }
    });
    assert.equal(rep.status, 201, JSON.stringify(rep.body));
    const rid = rep.body.data.id || rep.body.report.id;

    const reporterBefore = db.findUserById(repId);
    const strikesBefore = Number(reporterBefore.strikes || 0);

    // Reject twice — second call must NOT add another strike.
    for (let i = 0; i < 2; i++) {
      const v = await t.request(`/api/v1/reports/${rid}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${modToken}` },
        body: { status: 'rejected' }
      });
      assert.equal(v.status, 200, JSON.stringify(v.body));
    }
    const reporterAfter = db.findUserById(repId);
    assert.equal(
      Number(reporterAfter.strikes || 0),
      strikesBefore + 1,
      'repeated reject verdicts must apply exactly one strike'
    );
  });

  it('connection request response leaks no PII (peer projection)', async () => {
    const peerToken = await loginAs(t, 'audit.peer@safesphere.test');
    const owner = db.findUserById('usr_audit_owner');
    assert.ok(owner && owner.safeId, 'owner has a Safe ID');

    const req = await t.request('/api/v1/connections', {
      method: 'POST',
      headers: { Authorization: `Bearer ${peerToken}` },
      body: { ownerSafeId: owner.safeId, scopes: ['sos_status'], mode: 'always' }
    });
    assert.equal(req.status, 201, JSON.stringify(req.body));

    const serialized = JSON.stringify(req.body);
    for (const leak of [
      'audit.owner@safesphere.test',
      '+918800400001',
      'emergencyContacts',
      'passwordHash',
      'refreshToken',
      'aadhaar',
      '"strikes"',
      '"banned"'
    ]) {
      assert.ok(!serialized.includes(leak), `connection response must not contain ${leak}`);
    }
  });
});
