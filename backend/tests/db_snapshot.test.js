/**
 * DB Snapshot Persistence Test Suite (Supabase Storage backend)
 *
 * Exercises backend/src/data/dbSnapshot.js against a REAL local HTTP server
 * that emulates the Supabase Storage REST surface — every fetch (hydrate and
 * upload) is a real in-process network call, no mocks of the module internals.
 *
 * 1. Roundtrip: DataStore A → serializeSnapshot → upload → hydrate DataStore B
 *    via real fetch + node:sqlite deserialize → rows survive
 * 2. First boot (remote 404): fresh start, uploads enabled
 * 3. Garbage payload (non-SQLite bytes): hydrate refuses, live DB untouched,
 *    uploads disabled
 * 4. Remote unreachable/500: fail-safe gate — fresh DB serves but uploads stay
 *    disabled (a fresh empty DB must never overwrite the good remote snapshot)
 * 5. Upload request shape: Bearer service key, x-upsert, SQLite image body
 * 6. Dirty check: unchanged DB skips re-upload; changed DB uploads again
 * 7. Feature gate: no Supabase env → zero network calls
 * 8. pruneExpiredRows: expired OTPs and invalid/expired sessions pruned
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const crypto = require('crypto');

const bcrypt = require('bcryptjs');
const dbSnapshot = require('../src/data/dbSnapshot');
const { DataStore, db } = require('../src/data/store');
const { createUser } = require('../src/models/userModel');

describe('DB Snapshot Persistence (Supabase Storage)', () => {
  const SAVED_ENV = { ...process.env };

  // Emulated Supabase Storage
  let storageServer;
  let storagePort;
  let storedObject = null;   // Buffer when the bucket holds a snapshot
  let uploadRequests = [];   // captured POST requests
  let failAll = false;       // when true, every request returns 500

  before(async () => {
    process.env.NODE_ENV = 'test';
    storageServer = http.createServer((req, res) => {
      if (failAll) {
        res.writeHead(500);
        res.end(JSON.stringify({ error: 'internal error' }));
        return;
      }
      if (req.url === '/storage/v1/object/safesphere-db/safesphere.db') {
        if (req.method === 'POST') {
          const chunks = [];
          req.on('data', (c) => chunks.push(c));
          req.on('end', () => {
            uploadRequests.push({
              auth: req.headers.authorization,
              upsert: req.headers['x-upsert'],
              body: Buffer.concat(chunks)
            });
            storedObject = uploadRequests[uploadRequests.length - 1].body;
            res.writeHead(200, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ Key: 'safesphere-db/safesphere.db' }));
          });
          return;
        }
        if (req.method === 'GET') {
          if (storedObject) {
            res.writeHead(200);
            res.end(storedObject);
          } else {
            res.writeHead(404);
            res.end(JSON.stringify({ error: 'Object not found' }));
          }
          return;
        }
      }
      res.writeHead(500);
      res.end(JSON.stringify({ error: 'internal error' }));
    });
    await new Promise((resolve) => storageServer.listen(0, '127.0.0.1', resolve));
    storagePort = storageServer.address().port;
    process.env.SUPABASE_URL = `http://127.0.0.1:${storagePort}`;
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-role-key';
    process.env.SUPABASE_SNAPSHOT_BUCKET = 'safesphere-db';
  });

  after(() => {
    process.env = SAVED_ENV;
    dbSnapshot.resetSnapshotStateForTests();
    storageServer.close();
  });

  it('first boot: remote 404 → fresh start with uploads enabled', async () => {
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];
    storedObject = null;
    failAll = false;

    const store = new DataStore(':memory:');
    const result = await dbSnapshot.hydrateStoreFromSnapshot(() => store);
    assert.equal(result.attempted, true);
    assert.equal(result.restored, false, 'nothing to restore on first boot');
    assert.equal(result.uploadsEnabled, true, 'fresh boot must enable uploads');
    store.close();
  });

  it('roundtrips a real DataStore: serialize → upload → hydrate (real fetch + deserialize) → rows survive', async () => {
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];
    failAll = false;

    
    

    // Store A: real SQLite file with a real user
    const storeA = new DataStore(':memory:');
    storeA.saveUser(createUser({
      name: 'Snapshot Survivor',
      email: 'snapshot.survivor@safesphere.test',
      phone: '+911234567890',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));

    // First-boot hydrate (remote empty → 404) enables uploads for this process
    const boot = await dbSnapshot.hydrateStoreFromSnapshot(() => storeA);
    assert.equal(boot.uploadsEnabled, true, 'first boot must enable uploads');

    // Persist from A: real fetch to the mock Storage, verify request shape
    const uploaded = await dbSnapshot.persistSnapshotNow(() => storeA);
    assert.equal(uploaded, true, 'first persist must upload');
    assert.equal(uploadRequests.length, 1);
    const req = uploadRequests[0];
    assert.equal(req.auth, 'Bearer test-service-role-key');
    assert.equal(req.upsert, 'true');
    assert.equal(req.body.slice(0, 15).toString('latin1'), 'SQLite format 3');

    // Store B: fresh empty file DB, then hydrate from the remote snapshot
    const storeB = new DataStore(':memory:');
    const before = storeB.findUserByEmail('snapshot.survivor@safesphere.test');
    assert.equal(before, null, 'store B starts empty');

    const result = await dbSnapshot.hydrateStoreFromSnapshot(() => storeB);
    assert.equal(result.attempted, true);
    assert.equal(result.restored, true, 'snapshot must be restored');
    assert.equal(result.uploadsEnabled, true);

    const survivor = storeB.findUserByEmail('snapshot.survivor@safesphere.test');
    assert.ok(survivor, 'user must survive the snapshot roundtrip');
    assert.equal(survivor.name, 'Snapshot Survivor');

    storeA.close();
    storeB.close();
  });

  it('garbage remote payload: hydrate refuses, live DB untouched, uploads disabled', async () => {
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];
    failAll = false;
    // Stored object is valid SQLite but we overwrite the wire payload by
    // uploading garbage directly through the mock:
    storedObject = Buffer.from('this is definitely not a sqlite database, just text', 'latin1');

    const store = new DataStore(':memory:');
    // Give the live store a row so we can prove deserialize did NOT run
    store.saveUser(createUser({
      name: 'Pre Existing',
      email: 'pre.existing@safesphere.test',
      phone: '+910000000009',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));

    const result = await dbSnapshot.hydrateStoreFromSnapshot(() => store);
    assert.equal(result.attempted, true);
    assert.equal(result.restored, false, 'garbage must not be restored');
    assert.equal(result.uploadsEnabled, false, 'uploads must be disabled after bad payload');

    // Live DB untouched
    const stillThere = store.findUserByEmail('pre.existing@safesphere.test');
    assert.ok(stillThere, 'existing rows must survive a refused hydrate');

    // And the fail-safe blocks uploads
    const uploaded = await dbSnapshot.persistSnapshotNow(() => store);
    assert.equal(uploaded, false, 'no upload may occur after refused hydrate');
    assert.equal(uploadRequests.length, 0);
    store.close();
  });

  it('remote 500: fail-safe gate keeps serving fresh but blocks uploads', async () => {
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];
    failAll = true;

    const store = new DataStore(':memory:');
    const result = await dbSnapshot.hydrateStoreFromSnapshot(() => store);
    assert.equal(result.attempted, true);
    assert.equal(result.restored, false);
    assert.equal(result.uploadsEnabled, false, 'failed hydrate must disable uploads');

    const uploaded = await dbSnapshot.persistSnapshotNow(() => store);
    assert.equal(uploaded, false, 'no upload may occur after failed hydrate');
    assert.equal(uploadRequests.length, 0, 'zero upload calls after failed hydrate');
    store.close();
    failAll = false;
  });

  it('dirty check: unchanged DB skips re-upload, changed DB uploads again', async () => {
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];
    failAll = false;
    storedObject = null;

    // Legitimate first boot (404) enables uploads for this process
    const bootStore = new DataStore(':memory:');
    const boot = await dbSnapshot.hydrateStoreFromSnapshot(() => bootStore);
    assert.equal(boot.uploadsEnabled, true, 'first boot must enable uploads');
    bootStore.close();

    const store = new DataStore(':memory:');
    assert.equal(await dbSnapshot.persistSnapshotNow(() => store), true, 'first persist uploads');
    assert.equal(await dbSnapshot.persistSnapshotNow(() => store), false, 'unchanged DB skipped');
    store.saveUser(createUser({
      name: 'Dirty Checker',
      email: 'dirty.checker@safesphere.test',
      phone: '+919876543210',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    }));
    assert.equal(await dbSnapshot.persistSnapshotNow(() => store), true, 'changed DB uploads');
    assert.equal(uploadRequests.length, 2, 'exactly two uploads total');
    store.close();
  });

  it('feature gate: unset Supabase env → no-ops with zero network calls', async () => {
    const savedUrl = process.env.SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    dbSnapshot.resetSnapshotStateForTests();
    uploadRequests = [];

    const store = new DataStore(':memory:');
    const result = await dbSnapshot.hydrateStoreFromSnapshot(() => store);
    assert.equal(result.attempted, false);
    assert.equal(result.uploadsEnabled, false);

    const uploaded = await dbSnapshot.persistSnapshotNow(() => store);
    assert.equal(uploaded, false);
    assert.equal(uploadRequests.length, 0, 'zero requests when unconfigured');
    store.close();
    process.env.SUPABASE_URL = savedUrl;
    process.env.SUPABASE_SERVICE_ROLE_KEY = savedKey;
  });

  it('pruneExpiredRows removes expired OTPs and invalid/expired sessions', () => {
    const store = new DataStore(':memory:');

    store.saveOtp('+910000000001', {
      code: '123456',
      purpose: 'login',
      attempts: 0,
      expiresAt: Date.now() - 60000, // expired
      cooldownUntil: Date.now() - 120000,
      createdAt: Date.now() - 120000
    });
    store.saveOtp('+910000000002', {
      code: '654321',
      purpose: 'login',
      attempts: 0,
      expiresAt: Date.now() + 60000, // live
      cooldownUntil: 0,
      createdAt: Date.now()
    });

    const created = createUser({
      name: 'Session Prune',
      email: 'session.prune@safesphere.test',
      phone: '+910000000003',
      passwordHash: bcrypt.hashSync('Str0ngPass!23', 8)
    });
    store.saveUser(created);
    const nowIso = new Date().toISOString();
    store.db.prepare(`
      INSERT INTO sessions (id, userId, refreshToken, refreshTokenHash, expiresAt, isValid, createdAt, lastUsedAt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run('sess_dead', created.id, 'rt', crypto.createHash('sha256').update('rt').digest('hex'),
      new Date(Date.now() - 86400000).toISOString(), 0, nowIso, nowIso); // invalid + expired

    const result = store.pruneExpiredRows();
    assert.ok(result.expiredOtpsDeleted >= 1, 'expired OTP must be deleted');
    assert.ok(result.expiredSessionsDeleted >= 1, 'dead session must be deleted');
    assert.ok(store.getOtp('+910000000001') === null, 'expired OTP gone');
    assert.ok(store.getOtp('+910000000002') !== null, 'live OTP retained');

    store.close();
  });
});
