/**
 * M1 Backend Hardening Comprehensive Tests (F1-F5, F7, F8, R3)
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const { DatabaseSync } = require('node:sqlite');

const { startTestServer } = require('./helpers/testApp');
const { DataStore, db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');
const { createReport } = require('../src/models/reportModel');
const { bootstrapAdminIfConfigured } = require('../src/services/bootstrapService');

describe('M1 Backend Hardening (F1-F5, F7, F8, R3)', () => {
  let t;
  const SAVED_ENV = { ...process.env };

  async function createVerifiedUser({ id, name, email, phone, role = 'citizen', banned = false, strikes = 0, reputationScore = 0, lat = null, lng = null }) {
    db.saveUser(createUser({
      id,
      name,
      email,
      phone,
      role,
      banned,
      strikes,
      reputationScore,
      phoneVerified: true,
      isActive: true,
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      lastKnownLat: lat,
      lastKnownLng: lng
    }));
    const login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: email, password: 'Str0ngPass!23' }
    });
    assert.equal(login.status, 200);
    return {
      id,
      email,
      phone,
      token: login.body.data.accessToken
    };
  }

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();
  });

  beforeEach(() => {
    db.reset();
    delete process.env.BOOTSTRAP_ADMIN_EMAIL;
    delete process.env.BOOTSTRAP_ADMIN_PASSWORD;
    delete process.env.BOOTSTRAP_ADMIN_PHONE;
    delete process.env.BOOTSTRAP_ADMIN_NAME;
    delete process.env.BOOTSTRAP_ADMIN_PIN;
  });

  after(async () => {
    process.env = SAVED_ENV;
    await t.close();
  });

  describe('F1: Per-thread reporter anonymity (?reportedBy guard)', () => {
    it('blocks anonymous and third-party ?reportedBy enumeration (including array spoofing) with 403, while allowing owner and admin', async () => {
      const alice = await createVerifiedUser({
        id: 'usr_f1_alice',
        name: 'Alice F1',
        email: 'alice.f1@safesphere.test',
        phone: '+919900000101'
      });
      const bob = await createVerifiedUser({
        id: 'usr_f1_bob',
        name: 'Bob F1',
        email: 'bob.f1@safesphere.test',
        phone: '+919900000102'
      });
      const admin = await createVerifiedUser({
        id: 'usr_f1_admin',
        name: 'Admin F1',
        email: 'admin.f1@safesphere.test',
        phone: '+919900000103',
        role: 'admin'
      });

      const created = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${alice.token}` },
        body: {
          type: 'Dark Area',
          description: 'No lighting near subway exit',
          location: 'Subway Exit 2',
          latitude: 28.6139,
          longitude: 77.2090
        }
      });
      assert.equal(created.status, 201);

      // Anonymous caller
      const anonRes = await t.request(`/api/v1/reports?reportedBy=${alice.id}`);
      assert.equal(anonRes.status, 403);
      assert.equal(anonRes.body.error.code, 'FORBIDDEN');

      // Other citizen
      const bobRes = await t.request(`/api/v1/reports?reportedBy=${alice.id}`, {
        headers: { Authorization: `Bearer ${bob.token}` }
      });
      assert.equal(bobRes.status, 403);
      assert.equal(bobRes.body.error.code, 'FORBIDDEN');

      // Array parameter spoofing (?reportedBy=&reportedBy=alice)
      const spoofRes = await t.request(`/api/v1/reports?reportedBy=&reportedBy=${alice.id}`, {
        headers: { Authorization: `Bearer ${bob.token}` }
      });
      assert.equal(spoofRes.status, 403);
      assert.equal(spoofRes.body.error.code, 'FORBIDDEN');

      // Owner self-query (both non-proximity and proximity)
      const ownRes = await t.request(`/api/v1/reports?reportedBy=${alice.id}`, {
        headers: { Authorization: `Bearer ${alice.token}` }
      });
      assert.equal(ownRes.status, 200);
      assert.equal(ownRes.body.count, 1);
      assert.equal(ownRes.body.data[0].reportedBy, alice.id);

      const ownNearRes = await t.request(`/api/v1/reports?reportedBy=${alice.id}&lat=28.6139&lng=77.2090&radiusKm=5`, {
        headers: { Authorization: `Bearer ${alice.token}` }
      });
      assert.equal(ownNearRes.status, 200);
      assert.equal(ownNearRes.body.count, 1);

      // Privileged admin query
      const adminRes = await t.request(`/api/v1/reports?reportedBy=${alice.id}`, {
        headers: { Authorization: `Bearer ${admin.token}` }
      });
      assert.equal(adminRes.status, 200);
      assert.equal(adminRes.body.count, 1);
      assert.equal(adminRes.body.data[0].reportedBy, alice.id);
    });
  });

  describe('F2: Honest safety markers (no synthetic marker_auto_* fabrication)', () => {
    it('returns count: 0 and [] in empty regions without creating synthetic marker_auto_* rows in SQLite', async () => {
      const beforeCount = db.getAllMarkers({ includeUnverified: true }).length;
      const res = await t.request('/api/v1/markers/nearby?lat=23.2032&lon=77.0853&radius=5');
      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.count, 0);
      assert.deepEqual(res.body.data, []);

      const afterMarkers = db.getAllMarkers({ includeUnverified: true });
      assert.equal(afterMarkers.length, beforeCount);
      assert.equal(afterMarkers.some((m) => String(m.id).startsWith('marker_auto_')), false);
    });
  });

  describe('F3: Rejected & expired report isolation + mapVisible=true', () => {
    it('hides rejected reports from public feed/by-id/comments, supports mapVisible=true, and blocks voting/commenting on rejected & expired reports', async () => {
      const author = await createVerifiedUser({
        id: 'usr_f3_author',
        name: 'Author F3',
        email: 'author.f3@safesphere.test',
        phone: '+919900000201'
      });
      const voter = await createVerifiedUser({
        id: 'usr_f3_voter',
        name: 'Voter F3',
        email: 'voter.f3@safesphere.test',
        phone: '+919900000202'
      });
      const admin = await createVerifiedUser({
        id: 'usr_f3_admin',
        name: 'Admin F3',
        email: 'admin.f3@safesphere.test',
        phone: '+919900000203',
        role: 'admin'
      });

      const rejectedRep = db.saveReport(createReport({
        id: 'rep_f3_rejected',
        type: 'Threat',
        description: 'False alarm report',
        location: 'Block A',
        latitude: 28.6139,
        longitude: 77.2090,
        status: 'rejected',
        verificationSource: 'moderator',
        reportedBy: author.id
      }));
      const verifiedModRep = db.saveReport(createReport({
        id: 'rep_f3_verified_mod',
        type: 'Dark Area',
        description: 'Broken pole verified by mod',
        location: 'Block B',
        latitude: 28.6140,
        longitude: 77.2091,
        status: 'verified',
        verificationSource: 'moderator',
        reportedBy: author.id
      }));
      const verifiedConsensusRep = db.saveReport(createReport({
        id: 'rep_f3_verified_con',
        type: 'Flooding',
        description: 'Waterlogged lane verified by consensus',
        location: 'Block C',
        latitude: 28.6141,
        longitude: 77.2092,
        status: 'verified',
        verificationSource: 'community_consensus',
        reportedBy: author.id
      }));
      const pendingRep = db.saveReport(createReport({
        id: 'rep_f3_pending',
        type: 'Obstruction',
        description: 'Fallen tree branch',
        location: 'Block D',
        latitude: 28.6142,
        longitude: 77.2093,
        status: 'pending',
        reportedBy: author.id,
        expiresAt: new Date(Date.now() + 3600 * 1000).toISOString()
      }));
      const resolvedRep = db.saveReport(createReport({
        id: 'rep_f3_resolved',
        type: 'Hazard',
        description: 'Pothole repaired',
        location: 'Block E',
        latitude: 28.6143,
        longitude: 77.2094,
        status: 'resolved',
        verificationSource: 'moderator',
        reportedBy: author.id
      }));
      const expiredRep = db.saveReport(createReport({
        id: 'rep_f3_expired',
        type: 'Threat',
        description: 'Old unverified alert',
        location: 'Block F',
        latitude: 28.6144,
        longitude: 77.2095,
        status: 'pending',
        reportedBy: author.id,
        expiresAt: new Date(Date.now() - 60 * 1000).toISOString()
      }));

      // Seed a comment on both rejected and expired reports to verify comment voting blocks
      const rejComment = db.saveReportComment({
        id: 'cmt_f3_rej',
        reportId: rejectedRep.id,
        userId: author.id,
        body: 'Initial comment before rejection'
      });
      const expComment = db.saveReportComment({
        id: 'cmt_f3_exp',
        reportId: expiredRep.id,
        userId: author.id,
        body: 'Initial comment before expiry'
      });

      // Public ?status=rejected and ?status=REJECTED must return 0
      const pubRejLower = await t.request('/api/v1/reports?status=rejected');
      assert.equal(pubRejLower.status, 200);
      assert.equal(pubRejLower.body.count, 0);

      const pubRejUpper = await t.request('/api/v1/reports?status=REJECTED', {
        headers: { Authorization: `Bearer ${author.token}` }
      });
      assert.equal(pubRejUpper.status, 200);
      assert.equal(pubRejUpper.body.count, 0);

      // Admin ?status=rejected returns rejected reports
      const adminRej = await t.request('/api/v1/reports?status=rejected', {
        headers: { Authorization: `Bearer ${admin.token}` }
      });
      assert.equal(adminRej.status, 200);
      assert.equal(adminRej.body.count, 1);
      assert.equal(adminRej.body.data[0].id, rejectedRep.id);

      // mapVisible=true returns ONLY verified (moderator + community_consensus), excluding pending/resolved/rejected/expired
      const mapRes = await t.request('/api/v1/reports?mapVisible=true');
      assert.equal(mapRes.status, 200);
      const mapIds = mapRes.body.data.map((r) => r.id);
      assert.ok(mapRes.body.data.every((r) => r.status === 'verified'));
      assert.ok(mapIds.includes(verifiedModRep.id));
      assert.ok(mapIds.includes(verifiedConsensusRep.id));
      assert.ok(!mapIds.includes(pendingRep.id));
      assert.ok(!mapIds.includes(resolvedRep.id));
      assert.ok(!mapIds.includes(rejectedRep.id));
      assert.ok(!mapIds.includes(expiredRep.id));

      // Non-privileged GET /:id and GET /:id/comments on rejected report return 404
      const getRejAuthor = await t.request(`/api/v1/reports/${rejectedRep.id}`, {
        headers: { Authorization: `Bearer ${author.token}` }
      });
      assert.equal(getRejAuthor.status, 404);
      const getRejComments = await t.request(`/api/v1/reports/${rejectedRep.id}/comments`, {
        headers: { Authorization: `Bearer ${voter.token}` }
      });
      assert.equal(getRejComments.status, 404);

      // Admin can still inspect rejected report by ID and its comments
      const getRejAdmin = await t.request(`/api/v1/reports/${rejectedRep.id}`, {
        headers: { Authorization: `Bearer ${admin.token}` }
      });
      assert.equal(getRejAdmin.status, 200);

      // Voting, commenting, comment-voting on rejected report -> 409 REPORT_REJECTED
      const voteRej = await t.request(`/api/v1/reports/${rejectedRep.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { vote: 'confirm' }
      });
      assert.equal(voteRej.status, 409);
      assert.equal(voteRej.body.error.code, 'REPORT_REJECTED');

      const commentRej = await t.request(`/api/v1/reports/${rejectedRep.id}/comments`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { body: 'Trying to comment on rejected' }
      });
      assert.equal(commentRej.status, 409);
      assert.equal(commentRej.body.error.code, 'REPORT_REJECTED');

      const cmtVoteRej = await t.request(`/api/v1/reports/${rejectedRep.id}/comments/${rejComment.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { vote: 'confirm' }
      });
      assert.equal(cmtVoteRej.status, 409);
      assert.equal(cmtVoteRej.body.error.code, 'REPORT_REJECTED');

      // Voting, commenting, comment-voting on expired report -> 409 REPORT_EXPIRED
      const voteExp = await t.request(`/api/v1/reports/${expiredRep.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { vote: 'confirm' }
      });
      assert.equal(voteExp.status, 409);
      assert.equal(voteExp.body.error.code, 'REPORT_EXPIRED');

      const commentExp = await t.request(`/api/v1/reports/${expiredRep.id}/comments`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { body: 'Trying to comment on expired' }
      });
      assert.equal(commentExp.status, 409);
      assert.equal(commentExp.body.error.code, 'REPORT_EXPIRED');

      const cmtVoteExp = await t.request(`/api/v1/reports/${expiredRep.id}/comments/${expComment.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { vote: 'confirm' }
      });
      assert.equal(cmtVoteExp.status, 409);
      assert.equal(cmtVoteExp.body.error.code, 'REPORT_EXPIRED');
    });
  });

  describe('F4 & F5: Quorum stability, active user filtering, and idempotent karma transitions', () => {
    it('locks quorumRequired at creation so passive GET /reports?lat=&lng= views cannot inflate quorum mid-vote', async () => {
      const author = await createVerifiedUser({
        id: 'usr_f4_author',
        name: 'Author F4',
        email: 'author.f4@safesphere.test',
        phone: '+919900000301',
        lat: 28.6139,
        lng: 77.2090
      });

      const created = await t.request('/api/v1/reports', {
        method: 'POST',
        headers: { Authorization: `Bearer ${author.token}` },
        body: {
          type: 'Dark Area',
          description: 'Streetlight outage',
          location: 'CP Circle',
          latitude: 28.6139,
          longitude: 77.2090
        }
      });
      assert.equal(created.status, 201);
      const reportId = created.body.data.id;
      assert.equal(created.body.data.quorumRequired, 5);

      // Simulate 25 passive authenticated citizens fetching the nearby feed
      for (let i = 0; i < 25; i++) {
        const lurker = await createVerifiedUser({
          id: `usr_f4_lurker_${i}`,
          name: `Lurker ${i}`,
          email: `lurker${i}.f4@safesphere.test`,
          phone: `+91990001${String(i).padStart(4, '0')}`
        });
        const feedRes = await t.request('/api/v1/reports?lat=28.6139&lng=77.2090&radiusKm=10', {
          headers: { Authorization: `Bearer ${lurker.token}` }
        });
        assert.equal(feedRes.status, 200);
      }

      // Report's locked quorumRequired must still be 5, so 5 confirms reach 7:3 consensus
      const afterLurk = await t.request(`/api/v1/reports/${reportId}`);
      assert.equal(afterLurk.status, 200);
      assert.equal(afterLurk.body.data.quorumRequired, 5);

      for (let i = 0; i < 5; i++) {
        const voter = await db.findUserById(`usr_f4_lurker_${i}`);
        const login = await t.request('/api/v1/auth/login', {
          method: 'POST',
          body: { emailOrPhone: voter.email, password: 'Str0ngPass!23' }
        });
        const voteRes = await t.request(`/api/v1/reports/${reportId}/vote`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${login.body.data.accessToken}` },
          body: { vote: 'confirm' }
        });
        assert.equal(voteRes.status, 200);
        assert.equal(voteRes.body.data.quorumRequired, 5);
        if (i === 4) {
          assert.equal(voteRes.body.data.status, 'verified');
          assert.equal(voteRes.body.data.verificationSource, 'community_consensus');
        }
      }
    });

    it('excludes banned and inactive users in countNearbyActiveUsers (including report authors)', () => {
      db.saveUser(createUser({
        id: 'usr_cnt_active',
        name: 'Active User',
        email: 'active.cnt@safesphere.test',
        phone: '+919900000401',
        passwordHash: 'hash',
        isActive: true,
        banned: false,
        lastKnownLat: 12.9716,
        lastKnownLng: 77.5946
      }));
      db.saveUser(createUser({
        id: 'usr_cnt_banned',
        name: 'Banned Reporter',
        email: 'banned.cnt@safesphere.test',
        phone: '+919900000402',
        passwordHash: 'hash',
        isActive: true,
        banned: true,
        lastKnownLat: 12.9717,
        lastKnownLng: 77.5947
      }));
      db.saveUser(createUser({
        id: 'usr_cnt_inactive',
        name: 'Inactive Reporter',
        email: 'inactive.cnt@safesphere.test',
        phone: '+919900000403',
        passwordHash: 'hash',
        isActive: false,
        banned: false,
        lastKnownLat: 12.9718,
        lastKnownLng: 77.5948
      }));
      db.saveReport(createReport({
        id: 'rep_cnt_banned',
        type: 'Hazard',
        description: 'Report from banned user',
        latitude: 12.9717,
        longitude: 77.5947,
        reportedBy: 'usr_cnt_banned'
      }));
      db.saveReport(createReport({
        id: 'rep_cnt_inactive',
        type: 'Hazard',
        description: 'Report from inactive user',
        latitude: 12.9718,
        longitude: 77.5948,
        reportedBy: 'usr_cnt_inactive'
      }));

      const count = db.countNearbyActiveUsers(12.9716, 77.5946, 5);
      assert.equal(count, 1);
    });

    it('reconciles karma, strikes, ban reversal, verificationSource, and self-verdict protection across status overrides', async () => {
      const reporter = await createVerifiedUser({
        id: 'usr_f5_rep',
        name: 'Reporter F5',
        email: 'rep.f5@safesphere.test',
        phone: '+919900000501',
        strikes: 2,
        reputationScore: 0
      });
      const mod = await createVerifiedUser({
        id: 'usr_f5_mod',
        name: 'Mod F5',
        email: 'mod.f5@safesphere.test',
        phone: '+919900000502',
        role: 'admin'
      });

      const rep = db.saveReport(createReport({
        id: 'rep_f5_override',
        type: 'Threat',
        description: 'Report subject to override',
        location: 'Sector 18',
        latitude: 28.5700,
        longitude: 77.3200,
        status: 'pending',
        reportedBy: reporter.id,
        expiresAt: new Date(Date.now() + 3600 * 1000).toISOString()
      }));

      // 1. Moderator verifies (+10 -> rep 10, strikes 2)
      let res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'verified' }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.verificationSource, 'moderator');
      assert.equal(db.findUserById(reporter.id).reputationScore, 10);

      // 2. Repeated verified status is idempotent (+10 stays +10)
      res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'verified' }
      });
      assert.equal(db.findUserById(reporter.id).reputationScore, 10);

      // 3. Moderator overrides verified -> rejected: reverses +10 and applies -20 + 1 strike (3 strikes => banned!)
      res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'rejected' }
      });
      assert.equal(res.status, 200);
      let userAfterReject = db.findUserById(reporter.id);
      assert.equal(userAfterReject.reputationScore, -20);
      assert.equal(userAfterReject.strikes, 3);
      assert.equal(userAfterReject.banned, true);

      // 4. Moderator reverses rejected -> verified: reverses -20 + strike (back to +10, strikes 2, unbanned!)
      res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'verified' }
      });
      assert.equal(res.status, 200);
      let userAfterVerify = db.findUserById(reporter.id);
      assert.equal(userAfterVerify.reputationScore, 10);
      assert.equal(userAfterVerify.strikes, 2);
      assert.equal(userAfterVerify.banned, false);

      // 5. verified -> resolved preserves +10
      res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'resolved' }
      });
      assert.equal(res.status, 200);
      assert.equal(db.findUserById(reporter.id).reputationScore, 10);

      // 6. resolved -> pending resets verificationSource to 'pending', restores expiresAt, and reverses +10 -> 0
      res = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'pending' }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.verificationSource, 'pending');
      assert.ok(res.body.data.expiresAt, 'expiresAt should be restored when returning to pending');
      assert.equal(db.findUserById(reporter.id).reputationScore, 0);

      // 7. Self-verdict protection: moderator cannot self-award +10 on own report
      const modRep = db.saveReport(createReport({
        id: 'rep_f5_self',
        type: 'Hazard',
        description: 'Mod own report',
        location: 'Sector 19',
        latitude: 28.5710,
        longitude: 77.3210,
        status: 'pending',
        reportedBy: mod.id
      }));
      const selfRes = await t.request(`/api/v1/reports/${modRep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${mod.token}` },
        body: { status: 'verified' }
      });
      assert.equal(selfRes.status, 200);
      assert.equal(db.findUserById(mod.id).reputationScore, 0);
    });
  });

  describe('F7: Test isolation & additive SQLite schema', () => {
    it('DataStore.reset() clears connections, connection_locations, and connection_checkins', () => {
      const now = new Date().toISOString();
      db.db.prepare(
        'INSERT INTO connections (id, ownerId, granteeId, status, createdAt) VALUES (?, ?, ?, ?, ?)'
      ).run('con_1', 'usr_a', 'usr_b', 'active', now);
      db.db.prepare(
        'INSERT INTO connection_locations (connectionId, latitude, longitude, accuracy, timestamp) VALUES (?, ?, ?, ?, ?)'
      ).run('con_1', 28.61, 77.20, 10, now);
      db.db.prepare(
        'INSERT INTO connection_checkins (connectionId, fromUserId, message, createdAt) VALUES (?, ?, ?, ?)'
      ).run('con_1', 'usr_a', 'Safe check-in', now);

      assert.equal(db._count('connections'), 1);
      assert.equal(db._count('connection_locations'), 1);
      assert.equal(db._count('connection_checkins'), 1);

      db.reset();

      assert.equal(db._count('connections'), 0);
      assert.equal(db._count('connection_locations'), 0);
      assert.equal(db._count('connection_checkins'), 0);
    });

    it('upgrades legacy SQLite snapshots additively (karmaDelta, strikeApplied, and _backfillPhoneCanonical)', () => {
      const legacy = new DatabaseSync(':memory:');
      legacy.exec(`
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          email TEXT NOT NULL,
          phone TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'citizen',
          passwordHash TEXT NOT NULL,
          pin TEXT,
          pinHash TEXT,
          biometricToken TEXT,
          biometricsEnabled INTEGER NOT NULL DEFAULT 0,
          emergencyContacts TEXT NOT NULL DEFAULT '[]',
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        );
        CREATE TABLE reports (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          description TEXT NOT NULL,
          location TEXT NOT NULL,
          latitude REAL,
          longitude REAL,
          status TEXT NOT NULL,
          reportedBy TEXT,
          attachments TEXT NOT NULL DEFAULT '[]',
          photoUrl TEXT,
          karmaAwarded INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        );
      `);
      const now = new Date().toISOString();
      legacy.prepare(
        'INSERT INTO users (id, name, email, phone, role, passwordHash, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run('usr_leg_1', 'Legacy User', 'leg1@safesphere.test', '+91 98765-43210', 'citizen', 'hash', now, now);
      legacy.prepare(
        'INSERT INTO users (id, name, email, phone, role, passwordHash, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run('usr_leg_2', 'Clash Existing', 'leg2@safesphere.test', '919111222333', 'citizen', 'hash', now, now);
      legacy.prepare(
        'INSERT INTO users (id, name, email, phone, role, passwordHash, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run('usr_leg_3', 'Clash Legacy', 'leg3@safesphere.test', '+91 91112-22333', 'citizen', 'hash', now, now);

      legacy.prepare(
        'INSERT INTO reports (id, type, description, location, status, karmaAwarded, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run('rep_leg_v', 'Hazard', 'Verified legacy', 'Loc V', 'verified', 1, now, now);
      legacy.prepare(
        'INSERT INTO reports (id, type, description, location, status, karmaAwarded, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run('rep_leg_r', 'Threat', 'Rejected legacy', 'Loc R', 'rejected', 1, now, now);

      const snapshotBuf = Buffer.from(legacy.serialize());
      legacy.close();

      const store = new DataStore();
      store.deserializeSnapshot(snapshotBuf);

      const u1 = store.findUserById('usr_leg_1');
      assert.equal(u1.phone, '919876543210', '_backfillPhoneCanonical must normalize legacy spaced phone');
      const u3 = store.findUserById('usr_leg_3');
      assert.equal(u3.phone, '+91 91112-22333', 'clashing phone must not be merged or fail initSchema');

      const rv = store.findReportById('rep_leg_v');
      assert.equal(rv.karmaDelta, 10);
      assert.equal(rv.strikeApplied, 0);
      const rr = store.findReportById('rep_leg_r');
      assert.equal(rr.karmaDelta, -20);
      assert.equal(rr.strikeApplied, 1);

      store.close();
    });
  });

  describe('F8: Env-gated admin bootstrap', () => {
    it('stays inactive when BOOTSTRAP_ADMIN_* env vars are unset and register() still assigns citizen', async () => {
      const outcome = bootstrapAdminIfConfigured(db);
      assert.equal(outcome.action, 'inactive');

      const reg = await t.request('/api/v1/auth/register', {
        method: 'POST',
        body: {
          name: 'Regular Citizen',
          email: 'citizen.f8@safesphere.test',
          phone: '+919900000601',
          password: 'Str0ngPass!23',
          role: 'admin'
        }
      });
      assert.equal(reg.status, 201);
      assert.equal(reg.body.user.role, 'citizen');
    });

    it('creates admin idempotently, logs in via /auth/login, approves reports, and enforces anti-hijack password check', async () => {
      const adminEmail = 'mod.bootstrap@safesphere.test';
      const adminPass = 'ModBootstrap#2026!';
      process.env.BOOTSTRAP_ADMIN_EMAIL = adminEmail;
      process.env.BOOTSTRAP_ADMIN_PASSWORD = adminPass;
      process.env.BOOTSTRAP_ADMIN_PHONE = '+919900000701';
      process.env.BOOTSTRAP_ADMIN_PIN = '2468';

      const first = bootstrapAdminIfConfigured(db);
      assert.equal(first.action, 'created');
      const second = bootstrapAdminIfConfigured(db);
      assert.equal(second.action, 'noop');

      const login = await t.request('/api/v1/auth/login', {
        method: 'POST',
        body: { emailOrPhone: adminEmail, password: adminPass }
      });
      assert.equal(login.status, 200);
      assert.equal(login.body.user.role, 'admin');
      assert.equal(login.body.user.phoneVerified, true);

      const citizen = await createVerifiedUser({
        id: 'usr_f8_cit',
        name: 'Citizen F8',
        email: 'cit.f8@safesphere.test',
        phone: '+919900000702'
      });
      const rep = db.saveReport(createReport({
        id: 'rep_f8_target',
        type: 'Dark Area',
        description: 'Needs mod review',
        location: 'Main Rd',
        latitude: 28.6139,
        longitude: 77.2090,
        reportedBy: citizen.id
      }));

      const modApprove = await t.request(`/api/v1/reports/${rep.id}/status`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${login.body.data.accessToken}` },
        body: { status: 'verified' }
      });
      assert.equal(modApprove.status, 200);
      assert.equal(modApprove.body.data.status, 'verified');

      // Anti-hijack: pre-existing citizen with different password cannot be promoted
      process.env.BOOTSTRAP_ADMIN_EMAIL = citizen.email;
      process.env.BOOTSTRAP_ADMIN_PASSWORD = 'WrongPassword!999';
      const hijackAttempt = bootstrapAdminIfConfigured(db);
      assert.equal(hijackAttempt.action, 'rejected');
      assert.equal(hijackAttempt.reason, 'password_mismatch');
      assert.equal(db.findUserById(citizen.id).role, 'citizen');
    });
  });

  describe('R3 Invariants: /sos/* and /location/* remain ungated even for anonymous and banned users', () => {
    it('allows unauthenticated and banned users to trigger SOS and start location share sessions', async () => {
      // Anonymous SOS + Share
      const anonSos = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090, triggerMethod: 'button' }
      });
      assert.equal(anonSos.status, 201);
      assert.equal(anonSos.body.success, true);

      const anonShare = await t.request('/api/v1/location/share-session', {
        method: 'POST',
        body: { latitude: 28.6139, longitude: 77.2090 }
      });
      assert.equal(anonShare.status, 201);
      assert.equal(anonShare.body.success, true);

      // Banned user SOS + Share
      const bannedUser = await createVerifiedUser({
        id: 'usr_r3_banned',
        name: 'Banned R3',
        email: 'banned.r3@safesphere.test',
        phone: '+919900000801',
        banned: true,
        strikes: 3
      });

      const bannedSos = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${bannedUser.token}` },
        body: { latitude: 28.6140, longitude: 77.2091, triggerMethod: 'shake' }
      });
      assert.equal(bannedSos.status, 201);
      assert.equal(bannedSos.body.success, true);

      const bannedShare = await t.request('/api/v1/location/share-session', {
        method: 'POST',
        headers: { Authorization: `Bearer ${bannedUser.token}` },
        body: { latitude: 28.6140, longitude: 77.2091 }
      });
      assert.equal(bannedShare.status, 201);
      assert.equal(bannedShare.body.success, true);
    });
  });
});
