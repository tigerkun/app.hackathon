/**
 * DB Snapshot Persistence — Supabase Storage backend
 *
 * Free-tier Render containers are ephemeral: the SQLite file is wiped on every
 * redeploy and spin-down, and persistent disks require a paid instance. This
 * module gives the existing synchronous SQLite layer real durability with a
 * minimal, audit-friendly design (100% in-process — no child processes):
 *
 *   Boot:  hydrateStoreFromSnapshot(db) downloads the latest snapshot from a
 *          PRIVATE Supabase Storage bucket and atomically loads it into the
 *          already-open DataStore via node:sqlite deserialize(). Called from
 *          server.js BEFORE server.listen(), so no request can race it.
 *   Run:   every SNAPSHOT_INTERVAL_MS (default 45s) the live DB is serialized
 *          via node:sqlite serialize(), sha256-compared against the last
 *          uploaded image (dirty check), and uploaded with x-upsert.
 *   Stop:  the SIGTERM/SIGINT shutdown chain flushes a final snapshot before
 *          db.close().
 *
 * Data-safety rules:
 *  - The feature is completely OFF unless SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 *    are set (local dev and tests are unaffected).
 *  - Remote payloads are validated against the SQLite magic header BEFORE they
 *    touch the live database.
 *  - If a configured hydrate FAILS (non-404), uploads are disabled for this
 *    process: the server still boots (offline-first invariant #1) but the fresh
 *    empty DB can never overwrite the good remote snapshot.
 *  - The service-role key is read from env only, never logged or returned.
 */

const crypto = require('crypto');

const SNAPSHOT_OBJECT = 'safesphere.db';
const SQLITE_MAGIC = 'SQLite format 3';
const HYDRATE_TIMEOUT_MS = 15000;

const state = {
  uploadsEnabled: false,
  lastUploadedHash: null,
  intervalHandle: null
};

function snapshotConfig() {
  const url = (process.env.SUPABASE_URL || '').trim();
  const key = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  const bucket = (process.env.SUPABASE_SNAPSHOT_BUCKET || 'safesphere-db').trim();
  return {
    url: url.replace(/\/+$/, ''),
    key,
    bucket,
    configured: Boolean(url && key)
  };
}

function isValidSQLiteImage(buf) {
  return Buffer.isBuffer(buf)
    && buf.length >= 100
    && buf.slice(0, 15).toString('latin1') === SQLITE_MAGIC;
}

/**
 * Downloads the remote snapshot and loads it into the open DataStore via
 * node:sqlite deserialize() (atomic image replacement). Safe to call before
 * server.listen() — no request can be served mid-hydration. In snapshot mode
 * the live DB is in-memory (see config/index.js), which is the guaranteed-safe
 * target for deserialize().
 *
 * Returns { attempted, restored, uploadsEnabled }:
 *  - attempted=false  → Supabase not configured (feature off)
 *  - restored=false   → remote empty (404, first boot) OR hydrate failed
 *  - uploadsEnabled   → whether this process may upload snapshots
 */
async function hydrateStoreFromSnapshot(getDb) {
  const { url, key, bucket, configured } = snapshotConfig();
  if (!configured) {
    return { attempted: false, restored: false, uploadsEnabled: false };
  }

  let res;
  try {
    res = await fetch(`${url}/storage/v1/object/${bucket}/${SNAPSHOT_OBJECT}`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(HYDRATE_TIMEOUT_MS)
    });
  } catch (err) {
    state.uploadsEnabled = false;
    console.warn(
      '[dbSnapshot] hydrate fetch failed — serving with an empty local DB. Remote snapshot uploads DISABLED for this process to prevent data loss.',
      err.message
    );
    return { attempted: true, restored: false, uploadsEnabled: false };
  }

  if (res.status === 404) {
    console.log('[dbSnapshot] no remote snapshot yet (first boot) — starting fresh');
    state.uploadsEnabled = true;
    return { attempted: true, restored: false, uploadsEnabled: true };
  }

  if (!res.ok) {
    // Supabase Storage quirk: a MISSING object comes back as HTTP 400 with an
    // inner { statusCode: "404", code: "NoSuchKey" } body, not a clean 404.
    // That shape is a legitimate first boot, not an infrastructure failure.
    let body = null;
    try { body = await res.json(); } catch (_) { body = null; }
    const isMissingObject = Boolean(
      body
      && (
        body.code === 'NoSuchKey'
        || String(body.statusCode) === '404'
        || /object not found/i.test(String(body.message || ''))
      )
    );
    if (isMissingObject) {
      console.log('[dbSnapshot] no remote snapshot yet (first boot, Supabase 400-NoSuchKey shape) — starting fresh');
      state.uploadsEnabled = true;
      return { attempted: true, restored: false, uploadsEnabled: true };
    }
    state.uploadsEnabled = false;
    console.warn(
      `[dbSnapshot] hydrate failed: HTTP ${res.status} — serving with an empty local DB. Remote snapshot uploads DISABLED for this process to prevent data loss.`
    );
    return { attempted: true, restored: false, uploadsEnabled: false };
  }

  let buf;
  try {
    buf = Buffer.from(await res.arrayBuffer());
  } catch (err) {
    state.uploadsEnabled = false;
    console.warn('[dbSnapshot] snapshot read failed:', err.message);
    return { attempted: true, restored: false, uploadsEnabled: false };
  }

  if (!isValidSQLiteImage(buf)) {
    state.uploadsEnabled = false;
    console.warn(
      '[dbSnapshot] remote snapshot is not a valid SQLite image — refusing to hydrate. Remote snapshot uploads DISABLED for this process to prevent data loss.'
    );
    return { attempted: true, restored: false, uploadsEnabled: false };
  }

  try {
    const store = getDb();
    if (!store || typeof store.deserializeSnapshot !== 'function') {
      throw new Error('DataStore does not expose deserializeSnapshot()');
    }
    store.deserializeSnapshot(buf);
  } catch (err) {
    state.uploadsEnabled = false;
    console.warn('[dbSnapshot] deserialize failed:', err.message,
      '— serving with an empty local DB. Remote snapshot uploads DISABLED for this process to prevent data loss.');
    return { attempted: true, restored: false, uploadsEnabled: false };
  }

  console.log(`[dbSnapshot] hydrated live DB from remote snapshot (${buf.length} bytes)`);
  state.uploadsEnabled = true;
  return { attempted: true, restored: true, uploadsEnabled: true };
}

/**
 * Serializes the live DataStore and uploads it when it differs from the last
 * uploaded image. Never throws; returns true when an upload was performed.
 */
async function persistSnapshotNow(getDb) {
  const { url, key, bucket, configured } = snapshotConfig();
  if (!configured || !state.uploadsEnabled) return false;

  let view;
  try {
    const raw = getDb().serializeSnapshot();
    view = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
  } catch (err) {
    console.warn('[dbSnapshot] serialize failed:', err.message);
    return false;
  }
  if (!isValidSQLiteImage(view)) {
    console.warn('[dbSnapshot] serialized image is not a valid SQLite DB — skipping upload');
    return false;
  }

  const hash = crypto.createHash('sha256').update(view).digest('hex');
  if (hash === state.lastUploadedHash) return false; // clean — nothing changed

  const res = await fetch(`${url}/storage/v1/object/${bucket}/${SNAPSHOT_OBJECT}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/octet-stream',
      'x-upsert': 'true'
    },
    body: view,
    signal: AbortSignal.timeout(HYDRATE_TIMEOUT_MS)
  });
  if (!res.ok) {
    // Do not treat a failed upload as success, and do not update the hash so
    // the next tick retries. Body text may echo metadata — log only the status.
    console.warn(`[dbSnapshot] snapshot upload failed: HTTP ${res.status}`);
    return false;
  }
  state.lastUploadedHash = hash;
  return true;
}

/**
 * Starts the periodic upload tick. Returns the interval handle (or null when
 * the feature is off). The shutdown flush lives in server.js shutdown().
 */
function startSnapshotPersistence(getDb, intervalMs = null) {
  const { configured } = snapshotConfig();
  if (!configured) return null;

  const raw = Number(intervalMs || process.env.SNAPSHOT_INTERVAL_MS || 45000);
  const ms = Math.max(10000, Number.isFinite(raw) ? raw : 45000);

  state.intervalHandle = setInterval(() => {
    try {
      // Hygiene: prune expired OTPs / invalid sessions so the durable snapshot
      // doesn't accumulate dead rows forever.
      const store = getDb();
      if (store && typeof store.pruneExpiredRows === 'function') {
        store.pruneExpiredRows();
      }
    } catch (_) {}
    persistSnapshotNow(getDb).catch((e) =>
      console.warn('[dbSnapshot] periodic upload error:', e.message)
    );
  }, ms);
  if (state.intervalHandle.unref) state.intervalHandle.unref();

  return state.intervalHandle;
}

/** Test isolation: resets upload-gating state without touching env config. */
function resetSnapshotStateForTests() {
  state.uploadsEnabled = false;
  state.lastUploadedHash = null;
  if (state.intervalHandle) {
    clearInterval(state.intervalHandle);
    state.intervalHandle = null;
  }
}

/** Test-only state inspection. */
function getSnapshotStateForTests() {
  return { ...state };
}

module.exports = {
  hydrateStoreFromSnapshot,
  persistSnapshotNow,
  startSnapshotPersistence,
  resetSnapshotStateForTests,
  getSnapshotStateForTests,
  isValidSQLiteImage,
  SNAPSHOT_OBJECT
};
