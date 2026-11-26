/**
 * Connections Test Suite (M3)
 *
 * Account-to-account trusted circle with SafeSphere IDs:
 * 1. Safe ID: generated at registration, `SF-XXXX-XX` unambiguous format,
 *    unique per user, usable to address connection requests
 * 2. Request flow: pending state exposes NOTHING, self-connection blocked,
 *    unknown Safe ID → 404, invalid scope/mode → 400, duplicates → 409
 *    (one live connection per pair; revoked connections may re-request)
 * 3. Respond: only owner accepts; grantee may withdraw; non-party → 403
 * 4. Scope auth matrix: grantee WITHOUT scope gets 403 SCOPE_NOT_GRANTED,
 *    revoked connection gets 403 CONNECTION_REVOKED (immediate, per-request)
 * 5. sos_only mode: location scope denied without an active SOS/tracking
 *    window, allowed during one; 'always' mode flows freely
 * 6. Beacon: owner-only pings, 200-point rolling cap, live read
 * 7. Check-in: 1 per 5 min rate limit (429 CHECKIN_RATE_LIMITED)
 *
 * Pairs under test (one live connection per pair):
 *   watcher  → owner  : connId       (always,  all scopes)
 *   stranger → owner  : sosOnlyConn  (sos_only, location)
 *   third    → owner  : narrowConn   (always,  sos_status only)
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');

const bcrypt = require('bcryptjs');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');
const { createUser, generateSafeId } = require('../src/models/userModel');

const SAFE_ID_RE = /^SF-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{2}$/;

async function loginAs(t, email) {
  const res = await t.request('/api/v1/auth/login', {
    method: 'POST',
    body: { emailOrPhone: email, password: 'Str0ngPass!23' }
  });
  assert.equal(res.status, 200, `login ${email} → ${res.status}: ${JSON.stringify(res.body)}`);
  return res.body.data.accessToken;
}

/** Creates an accepted connection: grantee requests owner's Safe ID, owner accepts. */
async function createAccepted(t, granteeToken, ownerToken, ownerSafeId, { scopes, mode }) {
  const req = await t.request('/api/v1/connections', {
    method: 'POST',
    headers: { Authorization: `Bearer ${granteeToken}` },
    body: { ownerSafeId, scopes, mode }
  });
  assert.equal(req.status, 201, `request → ${req.status}: ${JSON.stringify(req.body)}`);
  const id = req.body.data.connection.id;
  const acc = await t.request(`/api/v1/connections/${id}/respond`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${ownerToken}` },
    body: { accept: true }
  });
  assert.equal(acc.status, 200, `accept → ${acc.status}: ${JSON.stringify(acc.body)}`);
  return id;
}

describe('Connections — Trusted Circle (M3)', () => {
  let t;
  let ownerToken;   // person being watched (owns the Safe ID)
  let watcherToken; // grantee #1
  let strangerToken;// grantee #2
  let thirdToken;   // grantee #3
  let ownerSafeId;
  let connId;       // active: always mode, all scopes
  let sosOnlyConn;  // active: sos_only mode, location scope
  let narrowConn;   // active: always mode, sos_status scope only

  before(async () => {
    process.env.NODE_ENV = 'test';
    t = await startTestServer();

    db.saveUser(createUser({
      id: 'usr_m3_owner',
      name: 'M3 Owner',
      email: 'm3.owner@safesphere.test',
      phone: '+918800300001',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    db.saveUser(createUser({
      id: 'usr_m3_watcher',
      name: 'M3 Watcher',
      email: 'm3.watcher@safesphere.test',
      phone: '+918800300002',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    db.saveUser(createUser({
      id: 'usr_m3_stranger',
      name: 'M3 Stranger',
      email: 'm3.stranger@safesphere.test',
      phone: '+918800300003',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    db.saveUser(createUser({
      id: 'usr_m3_third',
      name: 'M3 Third',
      email: 'm3.third@safesphere.test',
      phone: '+918800300004',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));

    ownerToken = await loginAs(t, 'm3.owner@safesphere.test');
    watcherToken = await loginAs(t, 'm3.watcher@safesphere.test');
    strangerToken = await loginAs(t, 'm3.stranger@safesphere.test');
    thirdToken = await loginAs(t, 'm3.third@safesphere.test');

    const ownerRow = db.findUserById('usr_m3_owner');
    assert.ok(SAFE_ID_RE.test(ownerRow.safeId), `safeId format: ${ownerRow.safeId}`);
    ownerSafeId = ownerRow.safeId;
  });

  after(async () => t.close());

  describe('Safe ID generation', () => {
    it('exposes safeId in /auth/me', async () => {
      const me = await t.request('/api/v1/auth/me', {
        headers: { Authorization: `Bearer ${ownerToken}` }
      });
      assert.equal(me.status, 200);
      assert.ok(SAFE_ID_RE.test(me.body.data.safeId));
    });

    it('generates unique Safe IDs per user', async () => {
      const ids = ['usr_m3_owner', 'usr_m3_watcher', 'usr_m3_stranger', 'usr_m3_third']
        .map((id) => db.findUserById(id).safeId);
      assert.equal(new Set(ids).size, 4);
    });

    it('generateSafeId avoids ambiguous characters', () => {
      for (let i = 0; i < 200; i++) {
        const id = generateSafeId();
        assert.ok(!/[O0I1]/.test(id.replace(/^SF-/, '')), `no ambiguous chars: ${id}`);
      }
    });

    it('backfills Safe IDs for pre-M3 user rows (live DB upgrade path)', () => {
      // Simulate a legacy row written before the safeId column had values.
      db.db.prepare(`
        INSERT INTO users (id, name, email, phone, role, passwordHash, isActive, createdAt, updatedAt)
        VALUES ('usr_legacy_no_safeid', 'Legacy User', 'legacy@safesphere.test', '+918800399999',
                'citizen', 'x', 1, ?, ?)
      `).run(new Date().toISOString(), new Date().toISOString());
      assert.equal(db.findUserById('usr_legacy_no_safeid').safeId, null);

      // Boot/snapshot-hydrate path re-runs initSchema → backfill runs.
      db.initSchema();

      const backed = db.findUserById('usr_legacy_no_safeid');
      assert.ok(SAFE_ID_RE.test(backed.safeId), `backfilled safeId format: ${backed.safeId}`);

      // Idempotent: a second pass must not change an existing ID.
      db.initSchema();
      assert.equal(db.findUserById('usr_legacy_no_safeid').safeId, backed.safeId);
    });
  });

  describe('Connection requests', () => {
    it('watcher sends a request addressed by Safe ID → 201 pending', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: {
          ownerSafeId,
          scopes: ['location', 'nearby_alerts', 'sos_status'],
          mode: 'always'
        }
      });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.connection.status, 'pending');
      assert.equal(res.body.data.connection.mode, 'always');
      assert.equal(res.body.data.owner.safeId, ownerSafeId);
      connId = res.body.data.connection.id;
    });

    it('pending connection exposes NOTHING via scoped reads', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/live`, {
        headers: { Authorization: `Bearer ${watcherToken}` }
      });
      assert.equal(res.status, 403);
      assert.equal(res.body.error.code, 'CONNECTION_REVOKED');
    });

    it('rejects self-connection → 400 SELF_CONNECTION', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { ownerSafeId, scopes: ['location'], mode: 'always' }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'SELF_CONNECTION');
    });

    it('unknown Safe ID → 404 OWNER_NOT_FOUND', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { ownerSafeId: 'SF-ZZZZ-ZZ', scopes: ['location'], mode: 'always' }
      });
      assert.equal(res.status, 404);
      assert.equal(res.body.error.code, 'OWNER_NOT_FOUND');
    });

    it('invalid scope → 400 INVALID_SCOPES', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { ownerSafeId, scopes: ['location', 'hacker'], mode: 'always' }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_SCOPES');
    });

    it('invalid mode → 400 INVALID_MODE', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { ownerSafeId, scopes: ['location'], mode: 'always_and_forever' }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_MODE');
    });

    it('duplicate live request → 409 CONNECTION_EXISTS', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { ownerSafeId, scopes: ['location'], mode: 'always' }
      });
      assert.equal(res.status, 409);
      assert.equal(res.body.error.code, 'CONNECTION_EXISTS');
    });

    it('requires auth → 401 without token', async () => {
      const res = await t.request('/api/v1/connections', {
        method: 'POST',
        body: { ownerSafeId, scopes: ['location'], mode: 'always' }
      });
      assert.equal(res.status, 401);
    });

    it('expires stale pending requests before scoped access is checked', async () => {
      const expiredId = 'conn_expired_pending';
      db.saveConnection({
        id: expiredId,
        ownerId: 'usr_m3_owner',
        granteeId: 'usr_m3_third',
        scopes: ['sos_status'],
        mode: 'always',
        status: 'pending',
        createdAt: new Date(Date.now() - 31 * 86400000).toISOString(),
        expiresAt: new Date(Date.now() - 86400000).toISOString()
      });

      const expired = db.findConnectionById(expiredId);
      assert.equal(expired.status, 'expired');
      const read = await t.request(`/api/v1/connections/${expiredId}/status`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(read.status, 403);
      assert.equal(read.body.error.code, 'CONNECTION_REVOKED');
    });
  });

  describe('Respond / accept flow', () => {
    it('grantee cannot self-accept → 403', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/respond`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { accept: true }
      });
      assert.equal(res.status, 403);
    });

    it('stranger cannot respond → 403 FORBIDDEN', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/respond`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${strangerToken}` },
        body: { accept: true }
      });
      assert.equal(res.status, 403);
    });

    it('owner accepts → active with acceptedAt', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/respond`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { accept: true }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.connection.status, 'active');
      assert.ok(res.body.data.connection.acceptedAt);
      assert.equal(res.body.data.connection.expiresAt, null);
    });

    it('double-respond → 409 CONNECTION_ALREADY_RESOLVED', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/respond`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { accept: true }
      });
      assert.equal(res.status, 409);
    });

    it('second pair: stranger → owner (sos_only, location) accepted', async () => {
      sosOnlyConn = await createAccepted(t, strangerToken, ownerToken, ownerSafeId, {
        scopes: ['location'],
        mode: 'sos_only'
      });
      assert.ok(sosOnlyConn);
    });

    it('third pair: third → owner (always, sos_status only) accepted', async () => {
      narrowConn = await createAccepted(t, thirdToken, ownerToken, ownerSafeId, {
        scopes: ['sos_status'],
        mode: 'always'
      });
      assert.ok(narrowConn);
    });
  });

  describe('Scope auth matrix (grantee without scope → 403)', () => {
    it('narrow connection (sos_status) cannot read /live → 403 SCOPE_NOT_GRANTED', async () => {
      const res = await t.request(`/api/v1/connections/${narrowConn}/live`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(res.status, 403);
      assert.equal(res.body.error.code, 'SCOPE_NOT_GRANTED');
    });

    it('narrow connection cannot read /alerts (grants sos_status only) → 403', async () => {
      const res = await t.request(`/api/v1/connections/${narrowConn}/alerts`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(res.status, 403);
      assert.equal(res.body.error.code, 'SCOPE_NOT_GRANTED');
    });

    it('narrow connection reads /status fine (grants sos_status)', async () => {
      const res = await t.request(`/api/v1/connections/${narrowConn}/status`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.owner.safeId, ownerSafeId);
      assert.equal(res.body.data.sosActive, false);
    });
  });

  describe('Beacon ping + live read', () => {
    it('watcher cannot ping someone else’s connection → 403', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/ping`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { latitude: 28.61, longitude: 77.21 }
      });
      assert.equal(res.status, 403);
    });

    it('invalid coordinates → 400 INVALID_COORDINATES', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/ping`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { latitude: 999, longitude: 77.21 }
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_COORDINATES');
    });

    it('owner pings → live read returns the beacon (always mode)', async () => {
      const ping = await t.request(`/api/v1/connections/${connId}/ping`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { latitude: 28.6139, longitude: 77.209, accuracy: 12 }
      });
      assert.equal(ping.status, 200);
      assert.equal(ping.body.data.location.latitude, 28.6139);

      const live = await t.request(`/api/v1/connections/${connId}/live`, {
        headers: { Authorization: `Bearer ${watcherToken}` }
      });
      assert.equal(live.status, 200);
      assert.equal(live.body.data.hasSignal, true);
      assert.equal(live.body.data.location.longitude, 77.209);
    });

    it('sos_only connection: live read denied WITHOUT an active SOS window', async () => {
      const res = await t.request(`/api/v1/connections/${sosOnlyConn}/live`, {
        headers: { Authorization: `Bearer ${strangerToken}` }
      });
      assert.equal(res.status, 403);
      assert.equal(res.body.error.code, 'SOS_ONLY_NO_ACTIVE_WINDOW');
    });

    it('sos_only connection: live read ALLOWED during an active SOS', async () => {
      const sos = await t.request('/api/v1/sos/trigger', {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { latitude: 28.62, longitude: 77.22, alertType: 'medical' }
      });
      assert.equal(sos.status, 201, `sos trigger: ${JSON.stringify(sos.body)}`);
      const alertId = sos.body.data.id;

      const live = await t.request(`/api/v1/connections/${sosOnlyConn}/live`, {
        headers: { Authorization: `Bearer ${strangerToken}` }
      });
      assert.equal(live.status, 200);

      const status = await t.request(`/api/v1/connections/${narrowConn}/status`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(status.status, 200);
      assert.equal(status.body.data.sosActive, true);
      assert.ok(status.body.data.sosAlert.id);

      const resolveToken = sos.body.data.resolveToken;
      const done = await t.request(`/api/v1/sos/${alertId}/resolve`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { resolveToken }
      });
      assert.equal(done.status, 200);
    });

    it('owner alerts scoped read returns the owner’s own alerts', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/alerts`, {
        headers: { Authorization: `Bearer ${watcherToken}` }
      });
      assert.equal(res.status, 200);
      assert.ok(Array.isArray(res.body.data.alerts));
    });
  });

  describe('Check-in ("check on them")', () => {
    it('watcher checks in → 200 with timestamp', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/checkin`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { message: 'Are you okay?' }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.message, 'Are you okay?');
      assert.ok(res.body.data.checkedInAt);
    });

    it('second check-in within 5 min → 429 CHECKIN_RATE_LIMITED', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/checkin`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { message: 'again' }
      });
      assert.equal(res.status, 429);
      assert.equal(res.body.error.code, 'CHECKIN_RATE_LIMITED');
    });

    it('owner cannot check in on their own connection → 403', async () => {
      const res = await t.request(`/api/v1/connections/${narrowConn}/checkin`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { message: 'self' }
      });
      assert.equal(res.status, 403);
    });
  });

  describe('Scope management + revocation (revoked → 403 immediately)', () => {
    it('grantee cannot adjust scopes → 403 (owner-only)', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/scopes`, {
        method: 'PATCH',
        headers: { Authorization: `Bearer ${watcherToken}` },
        body: { scopes: ['sos_status'] }
      });
      assert.equal(res.status, 403);
    });

    it('owner narrows scopes → subsequent out-of-scope read 403s', async () => {
      const patch = await t.request(`/api/v1/connections/${connId}/scopes`, {
        method: 'PATCH',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { scopes: ['sos_status'] }
      });
      assert.equal(patch.status, 200);
      assert.deepEqual(patch.body.data.connection.scopes, ['sos_status']);

      const live = await t.request(`/api/v1/connections/${connId}/live`, {
        headers: { Authorization: `Bearer ${watcherToken}` }
      });
      assert.equal(live.status, 403);
      assert.equal(live.body.error.code, 'SCOPE_NOT_GRANTED');

      const restore = await t.request(`/api/v1/connections/${connId}/scopes`, {
        method: 'PATCH',
        headers: { Authorization: `Bearer ${ownerToken}` },
        body: { scopes: ['location', 'nearby_alerts', 'sos_status'] }
      });
      assert.equal(restore.status, 200);
    });

    it('mine lists both directions with counterparts', async () => {
      const res = await t.request('/api/v1/connections/mine', {
        headers: { Authorization: `Bearer ${ownerToken}` }
      });
      assert.equal(res.status, 200);
      assert.ok(res.body.data.incoming.length >= 3);
      assert.ok(res.body.data.incoming.every((c) => c.counterpart && c.counterpart.safeId));
    });

    it('stranger cannot revoke → 403 FORBIDDEN', async () => {
      const res = await t.request(`/api/v1/connections/${connId}/revoke`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${strangerToken}` }
      });
      assert.equal(res.status, 403);
    });

    it('grantor revokes → every scoped read 403s CONNECTION_REVOKED immediately', async () => {
      const rev = await t.request(`/api/v1/connections/${sosOnlyConn}/revoke`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${ownerToken}` }
      });
      assert.equal(rev.status, 200);
      assert.equal(rev.body.data.connection.status, 'revoked');
      assert.ok(rev.body.data.connection.revokedAt);

      const live = await t.request(`/api/v1/connections/${sosOnlyConn}/live`, {
        headers: { Authorization: `Bearer ${strangerToken}` }
      });
      assert.equal(live.status, 403);
      assert.equal(live.body.error.code, 'CONNECTION_REVOKED');

      const status = await t.request(`/api/v1/connections/${connId}/status`, {
        headers: { Authorization: `Bearer ${watcherToken}` }
      });
      assert.equal(status.status, 200); // untouched connection still fine
    });

    it('grantee revokes from their side too', async () => {
      const rev = await t.request(`/api/v1/connections/${narrowConn}/revoke`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(rev.status, 200);
      const status = await t.request(`/api/v1/connections/${narrowConn}/status`, {
        headers: { Authorization: `Bearer ${thirdToken}` }
      });
      assert.equal(status.status, 403);
      assert.equal(status.body.error.code, 'CONNECTION_REVOKED');
    });
  });

  describe('Pending withdrawal + re-request after revocation', () => {
    it('grantee can withdraw their own pending request; pair can re-request after revocation', async () => {
      // stranger's sosOnlyConn was revoked above → re-request allowed
      const req = await t.request('/api/v1/connections', {
        method: 'POST',
        headers: { Authorization: `Bearer ${strangerToken}` },
        body: { ownerSafeId, scopes: ['location'], mode: 'sos_only' }
      });
      assert.equal(req.status, 201, `re-request → ${req.status}: ${JSON.stringify(req.body)}`);
      const id = req.body.data.connection.id;

      const res = await t.request(`/api/v1/connections/${id}/respond`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${strangerToken}` },
        body: { accept: false }
      });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.connection.status, 'revoked');
    });
  });

  describe('Beacon buffer cap', () => {
    it('connection_locations roll at 200 points', () => {
      for (let i = 0; i < 210; i++) {
        db.saveConnectionLocation({
          connectionId: connId,
          latitude: 28.6 + i / 10000,
          longitude: 77.2 + i / 10000,
          accuracy: 10
        });
      }
      const count = db.db.prepare(
        'SELECT COUNT(*) AS c FROM connection_locations WHERE connectionId = ?'
      ).get(connId);
      assert.equal(Number(count.c), 200);
    });
  });

  describe('Account deletion cascade (no orphan M3 rows)', () => {
    it('deleting a user purges their connections, locations, checkins, and votes', () => {
      // Two fresh users with a live connection + beacon + checkin + a report vote.
      const owner = db.saveUser(createUser({
        id: 'usr_cascade_owner', name: 'Cascade Owner',
        email: 'cascade.owner@safesphere.test', phone: '+918800700001',
        passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
      }));
      const grantee = db.saveUser(createUser({
        id: 'usr_cascade_grantee', name: 'Cascade Grantee',
        email: 'cascade.grantee@safesphere.test', phone: '+918800700002',
        passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
      }));

      const conn = db.saveConnection({
        id: 'conn_cascade_1', ownerId: owner.id, granteeId: grantee.id,
        scopes: ['location'], mode: 'always', status: 'active',
        createdAt: new Date().toISOString()
      });
      db.saveConnectionLocation({ connectionId: conn.id, latitude: 28.61, longitude: 77.21, accuracy: 8 });
      db.saveConnectionCheckin({ connectionId: conn.id, fromUserId: grantee.id, message: 'ok?' });

      // A report the grantee voted on (vote must be purged too).
      const { createReport } = require('../src/models/reportModel');
      const report = db.saveReport(createReport({
        id: 'rep_cascade_1', type: 'hazard', description: 'cascade vote target',
        latitude: 28.61, longitude: 77.21, reportedBy: owner.id
      }));
      db.saveReportVote({ id: 'vote_cascade_1', reportId: report.id, userId: grantee.id, vote: 'confirm', createdAt: new Date().toISOString() });
      assert.ok(db.getUserReportVote(report.id, grantee.id), 'vote exists pre-delete');

      // Delete the OWNER — every row touching them must vanish.
      db.deleteUser(owner.id);

      assert.equal(db.findConnectionById(conn.id), null, 'connection purged');
      assert.equal(
        db.db.prepare('SELECT COUNT(*) AS c FROM connection_locations WHERE connectionId = ?').get(conn.id).c, 0,
        'beacon locations purged'
      );
      assert.equal(db.getConnectionCheckins(conn.id).length, 0, 'checkins purged');
      // The grantee's vote on the owner's report SURVIVES owner deletion
      // (only the grantee's own deletion purges it — covered in the next test).
      assert.ok(db.getUserReportVote(report.id, grantee.id), 'grantee vote survives owner delete');
      assert.ok(db.findReportById(report.id), 'report survives (reportedBy nulled)');
      assert.equal(db.findReportById(report.id).reportedBy, null, 'reportedBy anonymized');

      // No orphan rows anywhere referencing the deleted owner.
      final_check_no_orphans(owner.id);
    });

    it('deleting the GRANTEE also purges the shared connection + their votes', () => {
      const owner = db.saveUser(createUser({
        id: 'usr_cascade2_owner', name: 'C2 Owner',
        email: 'c2.owner@safesphere.test', phone: '+918800700003',
        passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
      }));
      const grantee = db.saveUser(createUser({
        id: 'usr_cascade2_grantee', name: 'C2 Grantee',
        email: 'c2.grantee@safesphere.test', phone: '+918800700004',
        passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
      }));
      const conn = db.saveConnection({
        id: 'conn_cascade_2', ownerId: owner.id, granteeId: grantee.id,
        scopes: ['sos_status'], mode: 'sos_only', status: 'active',
        createdAt: new Date().toISOString()
      });
      // Grantee casts a vote that must be purged when THEY are deleted.
      const { createReport } = require('../src/models/reportModel');
      const report2 = db.saveReport(createReport({
        id: 'rep_cascade_2', type: 'hazard', description: 'grantee vote target',
        latitude: 28.62, longitude: 77.22, reportedBy: owner.id
      }));
      db.saveReportVote({ id: 'vote_cascade_2', reportId: report2.id, userId: grantee.id, vote: 'decline', createdAt: new Date().toISOString() });
      assert.ok(db.getUserReportVote(report2.id, grantee.id), 'grantee vote exists pre-delete');

      db.deleteUser(grantee.id);
      assert.equal(db.findConnectionById(conn.id), null, 'shared connection purged on grantee delete');
      assert.equal(db.getUserReportVote(report2.id, grantee.id) ?? null, null, 'grantee vote purged on their delete');
      final_check_no_orphans(grantee.id);
    });
  });
});

/** Asserts zero rows in any user-referencing table still point at userId. */
function final_check_no_orphans(userId) {
  const tables = [
    ['connections', 'ownerId'], ['connections', 'granteeId'],
    ['report_votes', 'userId'], ['sessions', 'userId'],
    ['alerts', 'userId'], ['tracking_sessions', 'userId'],
  ];
  for (const [table, col] of tables) {
    const row = db.db.prepare(`SELECT COUNT(*) AS c FROM ${table} WHERE ${col} = ?`).get(userId);
    assert.equal(Number(row.c), 0, `no orphan rows in ${table}.${col} for ${userId}`);
  }
}
