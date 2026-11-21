/**
 * Community Trust System Test Suite (M2)
 *
 * 1. Report auth-gating: guest submit → 401 SIGN_IN_REQUIRED
 * 2. Freshness: unverified reports >24h old drop from the default feed,
 *    stay visible to moderators and the report owner
 * 3. Voting: one vote per user per report, vote switching, tallies on list
 * 4. Reputation & strikes: verified → +10, rejected → -20 +1 strike,
 *    3 strikes → banned
 * 5. Ban enforcement: banned users get 403 INSUFFICIENT_REPUTATION on report
 *    submission and voting — but SOS triggering is NEVER blocked
 * 6. Aadhaar-lite: salted SHA-256 of last-4 only, never plaintext
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

const bcrypt = require('bcryptjs');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');
const { createReport } = require('../src/models/reportModel');

describe('Community Trust System (M2)', () => {
  let t;
  let adminToken;
  let citizenToken;
  let citizenId;
  let otherToken;

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();

    // Admin (moderator verdicts)
    db.saveUser(createUser({
      id: 'usr_m2_admin',
      name: 'M2 Admin',
      email: 'm2.admin@safesphere.test',
      phone: '+918800100001',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'admin'
    }));
    const adminLogin = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'm2.admin@safesphere.test', password: 'Str0ngPass!23' }
    });
    adminToken = adminLogin.body.data.accessToken;

    // Citizen 1 (reporter)
    db.saveUser(createUser({
      id: 'usr_m2_citizen1',
      name: 'M2 Citizen One',
      email: 'm2.citizen1@safesphere.test',
      phone: '+918800100002',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'citizen'
    }));
    const c1Login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'm2.citizen1@safesphere.test', password: 'Str0ngPass!23' }
    });
    citizenToken = c1Login.body.data.accessToken;
    citizenId = c1Login.body.data.user.id;

    // Citizen 2 (voter / second reporter)
    db.saveUser(createUser({
      id: 'usr_m2_citizen2',
      name: 'M2 Citizen Two',
      email: 'm2.citizen2@safesphere.test',
      phone: '+918800100003',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'citizen'
    }));
    const c2Login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'm2.citizen2@safesphere.test', password: 'Str0ngPass!23' }
    });
    otherToken = c2Login.body.data.accessToken;
  });

  after(async () => {
    await t.close();
  });

  function submitReport(token, overrides = {}) {
    return t.request('/api/v1/reports', {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: {
        type: 'Theft',
        description: 'M2 trust test report',
        location: 'test location',
        latitude: 28.61,
        longitude: 77.21,
        ...overrides
      }
    });
  }

  it('guest report submission → 401 UNAUTHORIZED (auth gate)', async () => {
    const res = await submitReport(null);
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'UNAUTHORIZED');
  });

  it('authenticated submission → 201 with 24h freshness expiry', async () => {
    const res = await submitReport(citizenToken);
    assert.equal(res.status, 201);
    assert.ok(res.body.data.expiresAt, 'unverified reports must carry expiresAt');
    const expiry = new Date(res.body.data.expiresAt).getTime();
    const created = new Date(res.body.data.createdAt).getTime();
    assert.ok(Math.abs(expiry - created - 24 * 3600 * 1000) < 1000, 'expiry = createdAt + 24h');
  });

  it('voting: one vote per user, switchable, tallies reported on the list', async () => {
    const create = await submitReport(citizenToken);
    const id = create.body.data.id;

    const v1 = await t.request(`/api/v1/reports/${id}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${otherToken}` },
      body: { vote: 'confirm' }
    });
    assert.equal(v1.status, 200);
    assert.equal(v1.body.data.upvotes, 1);
    assert.equal(v1.body.data.downvotes, 0);

    // Switch the vote to decline (overwrite, not a second vote)
    const v2 = await t.request(`/api/v1/reports/${id}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${otherToken}` },
      body: { vote: 'decline' }
    });
    assert.equal(v2.status, 200);
    assert.equal(v2.body.data.upvotes, 0);
    assert.equal(v2.body.data.downvotes, 1);

    // Invalid vote value → 400
    const bad = await t.request(`/api/v1/reports/${id}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${otherToken}` },
      body: { vote: 'meh' }
    });
    assert.equal(bad.status, 400);

    // Guest vote → 401
    const guestVote = await t.request(`/api/v1/reports/${id}/vote`, {
      method: 'POST',
      body: { vote: 'confirm' }
    });
    assert.equal(guestVote.status, 401);

    // List includes tallies + myVote for the authenticated caller
    const list = await t.request('/api/v1/reports', {
      headers: { Authorization: `Bearer ${otherToken}` }
    });
    assert.equal(list.status, 200);
    const mine = list.body.data.find(r => r.id === id);
    assert.ok(mine, 'report present in list');
    assert.equal(mine.upvotes, 0);
    assert.equal(mine.downvotes, 1);
    assert.equal(mine.myVote, 'decline');
  });

  it('freshness: unverified reports older than 24h drop from the default feed', async () => {
    // Backdate a pending report beyond the 24h window
    const stale = db.saveReport(createReport({
      type: 'Theft',
      description: 'stale unverified incident',
      location: 'old town',
      status: 'pending',
      reportedBy: citizenId,
      createdAt: new Date(Date.now() - 25 * 3600 * 1000).toISOString(),
      updatedAt: new Date(Date.now() - 25 * 3600 * 1000).toISOString()
    }));

    const list = await t.request('/api/v1/reports');
    assert.equal(list.status, 200);
    const found = list.body.data.find(r => r.id === stale.id);
    assert.equal(found, undefined, 'stale unverified report must be hidden');

    // Owner still sees their own stale report
    const ownerList = await t.request('/api/v1/reports', {
      headers: { Authorization: `Bearer ${citizenToken}` }
    });
    const ownerSeen = ownerList.body.data.find(r => r.id === stale.id);
    assert.ok(ownerSeen, 'owner sees their own stale report');

    // Moderator sees it too
    const modList = await t.request('/api/v1/reports', {
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    const modSeen = modList.body.data.find(r => r.id === stale.id);
    assert.ok(modSeen, 'moderator sees stale reports for review');
  });

  it('reputation & strikes: verified → +10; 3 rejects → banned → 403 on reports but SOS NEVER blocked', async () => {
    // Fresh reporter
    db.saveUser(createUser({
      id: 'usr_m2_reporter',
      name: 'M2 Reporter',
      email: 'm2.reporter@safesphere.test',
      phone: '+918800100004',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'citizen'
    }));
    const login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'm2.reporter@safesphere.test', password: 'Str0ngPass!23' }
    });
    const reporterToken = login.body.data.accessToken;
    const reporterId = login.body.data.user.id;

    // 3 rejected reports → -60 reputation, 3 strikes, banned
    for (let i = 0; i < 3; i++) {
      const create = await submitReport(reporterToken, { description: `false report ${i + 1}` });
      const verdict = await t.request(`/api/v1/reports/${create.body.data.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${adminToken}` },
        body: { status: 'rejected' }
      });
      assert.equal(verdict.status, 200);
    }

    const reporterUser = db.findUserById(reporterId);
    assert.equal(reporterUser.reputationScore, -60);
    assert.equal(reporterUser.strikes, 3);
    assert.equal(reporterUser.banned, true);

    // Banned user cannot submit reports
    const blocked = await submitReport(reporterToken);
    assert.equal(blocked.status, 403);
    assert.equal(blocked.body.error.code, 'INSUFFICIENT_REPUTATION');

    // Banned user cannot vote
    const voteBlocked = await t.request('/api/v1/reports/nonexistent/vote', {
      method: 'POST',
      headers: { Authorization: `Bearer ${reporterToken}` },
      body: { vote: 'confirm' }
    });
    assert.equal(voteBlocked.status, 403);

    // ⚠️ Safety invariant: SOS is NEVER blocked for banned users
    const sos = await t.request('/api/v1/sos/trigger', {
      method: 'POST',
      headers: { Authorization: `Bearer ${reporterToken}` },
      body: { latitude: 28.61, longitude: 77.21 }
    });
    assert.equal(sos.status, 201);
    assert.equal(sos.body.data.userId, reporterId);
    await t.request(`/api/v1/sos/${sos.body.data.id}/resolve`, {
      method: 'POST',
      body: { notes: 'test cleanup' }
    });

    // Verified reports clear expiry + add reputation (+10)
    db.saveUser(createUser({
      id: 'usr_m2_reporter2',
      name: 'M2 Reporter Two',
      email: 'm2.reporter2@safesphere.test',
      phone: '+918800100005',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: 'citizen'
    }));
    const login2 = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: 'm2.reporter2@safesphere.test', password: 'Str0ngPass!23' }
    });
    const token2 = login2.body.data.accessToken;
    const create2 = await submitReport(token2);
    await t.request(`/api/v1/reports/${create2.body.data.id}/status`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${adminToken}` },
      body: { status: 'verified' }
    });
    const verifiedUser = db.findUserById(login2.body.data.user.id);
    assert.equal(verifiedUser.reputationScore, 10);
    const verifiedAlert = db.findReportById(create2.body.data.id);
    assert.equal(verifiedAlert.expiresAt, null, 'verified reports persist (expiry cleared)');
  });

  it('aadhaar-lite: salted hash stored, plaintext never returned', async () => {
    const link = await t.request('/api/v1/auth/aadhaar/link', {
      method: 'POST',
      headers: { Authorization: `Bearer ${citizenToken}` },
      body: { aadhaarLast4: '1234' }
    });
    assert.equal(link.status, 200);
    assert.equal(link.body.data.aadhaarLinked, true);

    const me = await t.request('/api/v1/auth/me', {
      headers: { Authorization: `Bearer ${citizenToken}` }
    });
    assert.equal(me.body.data.aadhaarLinked, true);
    const serialized = JSON.stringify(me.body);
    assert.ok(!serialized.includes('1234'), 'raw last-4 must never echo back');
    assert.ok(!serialized.includes('aadhaarLast4Salt'), 'salt never exposed via API');
    assert.ok(!serialized.includes('aadhaarLast4Hash'), 'hash never exposed via API');

    const bad = await t.request('/api/v1/auth/aadhaar/link', {
      method: 'POST',
      headers: { Authorization: `Bearer ${citizenToken}` },
      body: { aadhaarLast4: '12' }
    });
    assert.equal(bad.status, 400);
  });
});
