/**
 * Reddit-style Community Reporting, Per-Thread Anonymity, 7:3 Dynamic Area Quorum,
 * Karma/Trust Scoring, Infrastructure Categories, and Comment Threads Tests.
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');

describe('Reddit-Style Community Reporting & Consensus System', () => {
  let t;
  const users = [];
  let adminToken;

  async function registerAndVerify(idx, opts = {}) {
    const email = `rc_${idx}_${Date.now()}@safesphere.test`;
    const phone = `+9197000${String(10000 + idx).slice(-5)}`;
    const id = `usr_rc_${idx}_${Date.now()}`;
    db.saveUser(createUser({
      id,
      name: `Citizen Tester ${idx}`,
      email,
      phone,
      phoneVerified: true,
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8),
      role: opts.role || 'citizen',
      lastKnownLat: opts.lat ?? null,
      lastKnownLng: opts.lng ?? null
    }));
    const login = await t.request('/api/v1/auth/login', {
      method: 'POST',
      body: { emailOrPhone: email, password: 'Str0ngPass!23' }
    });
    return {
      id,
      email,
      token: login.body.data.accessToken
    };
  }

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();
    const admin = await registerAndVerify(0, { role: 'admin' });
    adminToken = admin.token;
    for (let i = 1; i <= 8; i++) {
      users.push(await registerAndVerify(i));
    }
  });

  after(async () => {
    await t.close();
  });

  it('supports crime and infrastructure categories with unlinkable per-thread anonymous tags', async () => {
    const author = users[0];
    const reader = users[1];

    const r1 = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${author.token}` },
      body: {
        type: 'Dark Area',
        description: 'Streetlights dead for 200m near underpass',
        location: 'MG Road Underpass',
        latitude: 28.6139,
        longitude: 77.2090
      }
    });
    assert.equal(r1.status, 201);
    assert.equal(r1.body.data.type, 'Dark Area');
    assert.ok(r1.body.data.authorTag.startsWith('Citizen #'));
    assert.equal(r1.body.data.authorKarma, 0);

    const r2 = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${author.token}` },
      body: {
        type: 'Flooding',
        description: 'Deep waterlogging blocking left lane',
        location: 'Station Road',
        latitude: 28.6140,
        longitude: 77.2095
      }
    });
    assert.equal(r2.status, 201);
    assert.notEqual(
      r1.body.data.authorTag,
      r2.body.data.authorTag,
      'Same author must receive distinct anonymous tags across different threads'
    );

    // Public reader must NOT receive raw reportedBy user ID
    const feed = await t.request(`/api/v1/reports/${r1.body.data.id}`, {
      headers: { Authorization: `Bearer ${reader.token}` }
    });
    assert.equal(feed.status, 200);
    assert.equal(feed.body.data.reportedBy, null);
    assert.equal(feed.body.data.authorTag, r1.body.data.authorTag);
  });

  it('promotes report to community_consensus and awards +10 Karma on 7:3 vote consensus (no double-award)', async () => {
    const reporter = await registerAndVerify(91);
    const created = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${reporter.token}` },
      body: {
        type: 'Road Hazard',
        description: 'Large open manhole unmarked at dusk',
        location: 'Outer Ring Road',
        latitude: 19.05,
        longitude: 72.83
      }
    });
    assert.equal(created.status, 201);
    const reportId = created.body.data.id;

    // 4 confirm, 1 decline = 5 votes (80% confirm >= 70% = 7:3 threshold)
    for (let i = 0; i < 4; i++) {
      const v = await t.request(`/api/v1/reports/${reportId}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${users[i].token}` },
        body: { vote: 'confirm' }
      });
      assert.equal(v.status, 200);
    }

    const finalVote = await t.request(`/api/v1/reports/${reportId}/vote`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${users[4].token}` },
      body: { vote: 'decline' }
    });
    assert.equal(finalVote.status, 200);
    assert.equal(finalVote.body.data.status, 'verified');
    assert.equal(finalVote.body.data.verificationSource, 'community_consensus');
    assert.equal(finalVote.body.data.authorKarma, 10);

    // Admin status update on already consensus-verified report must not double-award karma
    const modRes = await t.request(`/api/v1/reports/${reportId}/status`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${adminToken}` },
      body: { status: 'verified' }
    });
    assert.equal(modRes.status, 200);
    assert.equal(db.findUserById(reporter.id).reputationScore, 10);
  });

  it('punishes false reports via <30% consensus -> negative Karma (-20) + strike, and scales quorum in dense areas', async () => {
    // Seed 28 active nearby users around (12.97, 77.64) -> ceil(28 * 0.25) = 7+ quorum
    for (let k = 0; k < 28; k++) {
      await registerAndVerify(200 + k, { lat: 12.97, lng: 77.64 });
    }
    // Pre-create extra nearby accounts BEFORE report creation so quorum doesn't shift mid-vote
    const extraNearbyVoters = [];
    for (let j = 0; j < 4; j++) {
      extraNearbyVoters.push(await registerAndVerify(300 + j, { lat: 12.97, lng: 77.64 }));
    }

    const falseReporter = await registerAndVerify(92, { lat: 12.97, lng: 77.64 });
    const rep = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${falseReporter.token}` },
      body: {
        type: 'Assault',
        description: 'False alarm test in crowded district',
        location: 'Indiranagar 100ft',
        latitude: 12.97,
        longitude: 77.64
      }
    });
    assert.equal(rep.status, 201);
    const quorum = rep.body.data.quorumRequired;
    assert.ok(quorum >= 8, `Expected area-scaled quorum >= 8, got ${quorum}`);

    // 5 downvotes alone should NOT verify/reject because quorum >= 8
    for (let i = 0; i < 5; i++) {
      const v = await t.request(`/api/v1/reports/${rep.body.data.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${users[i].token}` },
        body: { vote: 'decline' }
      });
      assert.equal(v.body.data.status, 'pending');
    }

    const remainingVoters = [...users.slice(5), ...extraNearbyVoters];
    for (let i = 5; i < quorum && (i - 5) < remainingVoters.length; i++) {
      await t.request(`/api/v1/reports/${rep.body.data.id}/vote`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${remainingVoters[i - 5].token}` },
        body: { vote: 'decline' }
      });
    }

    const updatedReporter = db.findUserById(falseReporter.id);
    assert.equal(updatedReporter.reputationScore, -20);
    assert.equal(updatedReporter.strikes, 1);
  });

  it('supports anonymous threaded comments, OP tag consistency, and comment voting', async () => {
    const poster = users[5];
    const commenter = users[6];
    const voter = users[7];

    const rep = await t.request('/api/v1/reports', {
      method: 'POST',
      headers: { Authorization: `Bearer ${poster.token}` },
      body: {
        type: 'Transit Issue',
        description: 'Bus stop lights flickering and unsafe wait area',
        location: 'Sector 18 Metro Gate 1',
        latitude: 28.57,
        longitude: 77.32
      }
    });
    assert.equal(rep.status, 201);
    const reportId = rep.body.data.id;

    // OP replies in comments -> same thread tag + isOp=true
    const opComment = await t.request(`/api/v1/reports/${reportId}/comments`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${poster.token}` },
      body: { body: 'Happening near exit 2 specifically.' }
    });
    assert.equal(opComment.status, 201);
    assert.equal(opComment.body.data.authorTag, rep.body.data.authorTag);
    assert.equal(opComment.body.data.isOp, true);

    // Other citizen replies -> different tag, isOp=false
    const otherComment = await t.request(`/api/v1/reports/${reportId}/comments`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${commenter.token}` },
      body: { body: 'Confirmed walking past here 10 minutes ago.', parentId: opComment.body.data.id }
    });
    assert.equal(otherComment.status, 201);
    assert.equal(otherComment.body.data.isOp, false);
    assert.notEqual(otherComment.body.data.authorTag, opComment.body.data.authorTag);

    // Self-vote on comment forbidden
    const selfCmtVote = await t.request(
      `/api/v1/reports/${reportId}/comments/${otherComment.body.data.id}/vote`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${commenter.token}` },
        body: { vote: 'confirm' }
      }
    );
    assert.equal(selfCmtVote.status, 403);

    // Third user upvotes comment
    const cmtVote = await t.request(
      `/api/v1/reports/${reportId}/comments/${otherComment.body.data.id}/vote`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${voter.token}` },
        body: { vote: 'confirm' }
      }
    );
    assert.equal(cmtVote.status, 200);
    assert.equal(cmtVote.body.data.upvotes, 1);

    // GET comments lists both
    const listRes = await t.request(`/api/v1/reports/${reportId}/comments`, {
      headers: { Authorization: `Bearer ${voter.token}` }
    });
    assert.equal(listRes.status, 200);
    assert.equal(listRes.body.data.length, 2);
  });
});
