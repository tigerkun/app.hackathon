/**
 * Connection Service
 * M3: consent-based trusted circle business logic. Connections let a grantee
 * (a trusted guardian) see scoped information about an owner (location,
 * nearby alerts, SOS status) — replacing the old share-link model with
 * account-to-account consent. Privacy rules:
 *   - Requests are addressed by the owner's public Safe ID (no email/phone).
 *   - Pending connections expose nothing until accepted.
 *   - mode 'sos_only' gates 'location' scope to active SOS/tracking windows.
 *   - Revocation is immediate — every scoped read re-verifies status.
 *   - Banned users cannot send connection requests.
 */

const crypto = require('crypto');
const { db } = require('../data/store');
const { toConnectionPeer } = require('../models/userModel');

const VALID_SCOPES = ['location', 'nearby_alerts', 'sos_status'];
const VALID_MODES = ['always', 'sos_only'];
const MAX_PENDING_REQUESTS_PER_USER = 20;
const MAX_CONNECTIONS_PER_USER = 25;
const CHECKIN_RATE_LIMIT_MS = 5 * 60 * 1000;
const PENDING_REQUEST_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function generateConnectionId() {
  return `conn_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

/**
 * Finds a user by their public Safe ID (SF-XXXX-XX format).
 */
function findUserBySafeId(safeId) {
  if (!safeId) return null;
  return db.db
    .prepare('SELECT * FROM users WHERE safeId = ? LIMIT 1')
    .get(String(safeId).trim().toUpperCase());
}

/**
 * Creates a pending connection request addressed by the owner's Safe ID.
 */
function requestConnection({ requester, ownerSafeId, scopes, mode }) {
  if (!Array.isArray(scopes) || scopes.length === 0) {
    const error = new Error('At least one scope is required (location, nearby_alerts, sos_status).');
    error.status = 400;
    error.code = 'INVALID_SCOPES';
    throw error;
  }
  for (const s of scopes) {
    if (!VALID_SCOPES.includes(s)) {
      const error = new Error(`Unknown scope: ${s}. Valid: ${VALID_SCOPES.join(', ')}`);
      error.status = 400;
      error.code = 'INVALID_SCOPES';
      throw error;
    }
  }
  const uniqueScopes = [...new Set(scopes)];

  if (!VALID_MODES.includes(mode)) {
    const error = new Error(`Invalid mode: ${mode}. Valid: ${VALID_MODES.join(', ')}`);
    error.status = 400;
    error.code = 'INVALID_MODE';
    throw error;
  }

  const owner = findUserBySafeId(ownerSafeId);
  if (!owner) {
    const error = new Error(`No SafeSphere user found with Safe ID ${ownerSafeId}.`);
    error.status = 404;
    error.code = 'OWNER_NOT_FOUND';
    throw error;
  }
  if (owner.id === requester.id) {
    const error = new Error('You cannot connect to your own Safe ID.');
    error.status = 400;
    error.code = 'SELF_CONNECTION';
    throw error;
  }
  if (owner.banned) {
    const error = new Error('This Safe ID belongs to a banned account.');
    error.status = 403;
    error.code = 'OWNER_BANNED';
    throw error;
  }
  // Banned users cannot send connection requests or retain scoped access —
  // documented invariant, previously unenforced on the requester side.
  if (requester.banned) {
    const error = new Error('Banned accounts cannot send connection requests.');
    error.status = 403;
    error.code = 'REQUESTER_BANNED';
    throw error;
  }

  // Existing live connection between the same pair? Report it rather than
  // duplicating. A REVOKED connection does not block re-requesting.
  const existing = db
    .listConnectionsByOwner(owner.id)
    .find((c) => c.granteeId === requester.id && (c.status === 'pending' || c.status === 'active'));
  if (existing) {
    const error = new Error(
      existing.status === 'pending'
        ? 'A connection request is already pending for this Safe ID.'
        : `A connection with this Safe ID already exists (${existing.status}).`
    );
    error.status = 409;
    error.code = 'CONNECTION_EXISTS';
    error.details = [{ connectionId: existing.id, status: existing.status }];
    throw error;
  }

  const pendingCount = db.countPendingConnectionRequests(owner.id);
  if (pendingCount >= MAX_PENDING_REQUESTS_PER_USER) {
    const error = new Error('This user has too many pending connection requests. Try again later.');
    error.status = 429;
    error.code = 'TOO_MANY_PENDING';
    throw error;
  }

  const requesterCount = db
    .listConnectionsByGrantee(requester.id)
    .filter((c) => c.status === 'pending' || c.status === 'active').length;
  if (requesterCount >= MAX_CONNECTIONS_PER_USER) {
    const error = new Error(`Connection limit reached (${MAX_CONNECTIONS_PER_USER}). Revoke one to add another.`);
    error.status = 429;
    error.code = 'CONNECTION_LIMIT_REACHED';
    throw error;
  }

  const conn = db.saveConnection({
    id: generateConnectionId(),
    ownerId: owner.id,
    granteeId: requester.id,
    scopes: uniqueScopes,
    mode,
    status: 'pending',
    createdAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + PENDING_REQUEST_TTL_MS).toISOString()
  });

  return {
    connection: conn,
    owner: toConnectionPeer(db.findUserById(owner.id))
  };
}

/**
 * Owner accepts a pending request. Returns the activated connection.
 */
function respondToConnection({ connectionId, responder, accept }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }

  const isOwner = conn.ownerId === responder.id;
  const isGrantee = conn.granteeId === responder.id;
  if (!isOwner && !isGrantee) {
    const error = new Error('You are not a party to this connection.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }

  if (conn.status !== 'pending') {
    const error = new Error(`Connection is already ${conn.status}.`);
    error.status = 409;
    error.code = 'CONNECTION_ALREADY_RESOLVED';
    throw error;
  }

  // Only the OWNER accepts/declines incoming requests; the grantee can
  // withdraw their own pending request (modeled as decline → revoked).
  if (accept && !isOwner) {
    const error = new Error('Only the connection owner can accept requests.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }

  return db.saveConnection({
    ...conn,
    status: accept ? 'active' : 'revoked',
    acceptedAt: accept ? new Date().toISOString() : conn.acceptedAt,
    revokedAt: accept ? null : new Date().toISOString(),
    expiresAt: null
  });
}

/**
 * Either party revokes an active connection — immediate and final.
 */
function revokeConnection({ connectionId, responder }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }

  const isOwner = conn.ownerId === responder.id;
  const isGrantee = conn.granteeId === responder.id;
  if (!isOwner && !isGrantee) {
    const error = new Error('You are not a party to this connection.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }

  if (conn.status !== 'active' && conn.status !== 'pending') {
    return conn;
  }

  return db.saveConnection({
    ...conn,
    status: 'revoked',
    revokedAt: new Date().toISOString()
  });
}

/**
 * Owner-only scope adjustment on an active connection.
 */
function updateScopes({ connectionId, ownerId, scopes }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }
  if (conn.ownerId !== ownerId) {
    const error = new Error('Only the connection owner can adjust scopes.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }
  if (conn.status !== 'active') {
    const error = new Error('Scopes can only be adjusted on active connections.');
    error.status = 409;
    error.code = 'CONNECTION_NOT_ACTIVE';
    throw error;
  }
  if (!Array.isArray(scopes) || scopes.length === 0) {
    const error = new Error(`scopes must be a non-empty array of: ${VALID_SCOPES.join(', ')}`);
    error.status = 400;
    error.code = 'INVALID_SCOPES';
    throw error;
  }
  for (const s of scopes) {
    if (!VALID_SCOPES.includes(s)) {
      const error = new Error(`Unknown scope: ${s}.`);
      error.status = 400;
      error.code = 'INVALID_SCOPES';
      throw error;
    }
  }

  return db.saveConnection({ ...conn, scopes: [...new Set(scopes)] });
}

/**
 * The core privacy gate: re-verifies per request that the viewer (grantee)
 * may read scoped data from this connection right now.
 * Returns the verified connection or throws an honest error.
 */
function verifyScopedAccess({ connectionId, viewerId, requiredScope }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }
  if (conn.granteeId !== viewerId) {
    const error = new Error('You are not the granted viewer of this connection.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }
  if (conn.status !== 'active') {
    const error = new Error(`Connection is ${conn.status} — access revoked.`);
    error.status = 403;
    error.code = 'CONNECTION_REVOKED';
    throw error;
  }
  // Banned grantees lose scoped access even on still-active connections.
  const viewer = db.findUserById(viewerId);
  if (viewer && viewer.banned) {
    const error = new Error('Banned accounts cannot access connection data.');
    error.status = 403;
    error.code = 'REQUESTER_BANNED';
    throw error;
  }
  if (!conn.scopes.includes(requiredScope)) {
    const error = new Error(`This connection does not include the '${requiredScope}' scope.`);
    error.status = 403;
    error.code = 'SCOPE_NOT_GRANTED';
    throw error;
  }

  // mode 'sos_only': 'location' scope only flows during an active SOS window
  if (conn.mode === 'sos_only' && requiredScope === 'location') {
    const owner = db.findUserById(conn.ownerId);
    const hasActiveSos = owner
      ? db
          .getActiveAlerts()
          .some((a) => a.userId === conn.ownerId && a.status === 'active')
      : false;
    const activeTracking = db
      .getActiveTrackingSessionsByUser(conn.ownerId)
      .some((s) => s.status === 'active');

    if (!hasActiveSos && !activeTracking) {
      const error = new Error('sos_only mode: no active SOS or tracking session right now.');
      error.status = 403;
      error.code = 'SOS_ONLY_NO_ACTIVE_WINDOW';
      throw error;
    }
  }

  return conn;
}

/** Beacon ping — stores location for the connection (owner's app posts it). */
function recordBeaconPing({ connectionId, owner, latitude, longitude, accuracy }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }
  if (conn.ownerId !== owner.id) {
    const error = new Error('Only the connection owner can beacon on it.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }
  if (conn.status !== 'active') {
    const error = new Error('Connection is not active.');
    error.status = 409;
    error.code = 'CONNECTION_NOT_ACTIVE';
    throw error;
  }
  // sos_only mode: beacons are only meaningful while an SOS/tracking window
  // is open — otherwise this would silently become always-on sharing.
  if (conn.mode === 'sos_only') {
    const hasActiveSos = db.getActiveAlerts().some((a) => a.userId === conn.ownerId && a.status === 'active');
    const activeTracking = db.getActiveTrackingSessionsByUser(conn.ownerId).some((s) => s.status === 'active');
    if (!hasActiveSos && !activeTracking) {
      const error = new Error('sos_only mode: beacons are only accepted during an active SOS or tracking session.');
      error.status = 403;
      error.code = 'SOS_ONLY_NO_ACTIVE_WINDOW';
      throw error;
    }
  }
  // Coordinate sanity — beacon points feed guardian maps.
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    const error = new Error('Valid latitude/longitude is required.');
    error.status = 400;
    error.code = 'INVALID_COORDINATES';
    throw error;
  }
  // Flood floor: beacons are meant every ~5min; sub-30s spam just churns rows.
  const lastPing = lastBeaconPingTimes.get(connectionId) || 0;
  if (Date.now() - lastPing < 30 * 1000) {
    const error = new Error('Beacon pings are limited to one every 30 seconds.');
    error.status = 429;
    error.code = 'BEACON_RATE_LIMITED';
    throw error;
  }
  lastBeaconPingTimes.set(connectionId, Date.now());

  db.saveConnectionLocation({ connectionId, latitude: lat, longitude: lng, accuracy });
  return db.getLatestConnectionLocation(connectionId);
}

const lastBeaconPingTimes = new Map(); // connectionId → lastPingMs

/** Check-in: grantee pings the owner — rate-limited to 1 per 5 minutes. */
const lastCheckInTimes = new Map(); // connectionId → lastCheckInMs (in-process)

function recordCheckIn({ connectionId, viewer, message }) {
  const conn = db.findConnectionById(connectionId);
  if (!conn) {
    const error = new Error('Connection not found.');
    error.status = 404;
    error.code = 'CONNECTION_NOT_FOUND';
    throw error;
  }
  if (conn.granteeId !== viewer.id || conn.status !== 'active') {
    const error = new Error('Connection not available for check-in.');
    error.status = 403;
    error.code = 'FORBIDDEN';
    throw error;
  }

  const key = `checkin:${connectionId}`;
  // Bound the in-process limiter: drop entries idle >1h so revoked/deleted
  // connections don't accumulate forever.
  if (lastCheckInTimes.size > 1000) {
    const cutoff = Date.now() - 60 * 60 * 1000;
    for (const [k, ts] of lastCheckInTimes) {
      if (ts < cutoff) lastCheckInTimes.delete(k);
    }
  }
  const last = lastCheckInTimes.get(key) || 0;
  const elapsed = Date.now() - last;
  if (elapsed < CHECKIN_RATE_LIMIT_MS) {
    const waitSeconds = Math.ceil((CHECKIN_RATE_LIMIT_MS - elapsed) / 1000);
    const error = new Error(`Please wait ${waitSeconds}s between check-ins.`);
    error.status = 429;
    error.code = 'CHECKIN_RATE_LIMITED';
    error.retryAfter = waitSeconds;
    throw error;
  }
  lastCheckInTimes.set(key, Date.now());

  const cleanMessage = String(message || 'Checking on you').slice(0, 200);
  const checkedInAt = new Date().toISOString();
  // Persist so the owner actually sees the ping in their circle view — the
  // grantee UI claims "they'll see you asked", which was previously false.
  db.saveConnectionCheckin({
    connectionId,
    fromUserId: viewer.id,
    message: cleanMessage,
    createdAt: checkedInAt
  });
  const viewerUser = db.findUserById(viewer.id);
  const ownerUser = db.findUserById(conn.ownerId);

  return {
    connectionId,
    ownerName: ownerUser ? ownerUser.name : 'SafeSphere user',
    fromName: viewerUser ? viewerUser.name : 'SafeSphere user',
    message: cleanMessage,
    checkedInAt
  };
}

module.exports = {
  requestConnection,
  respondToConnection,
  revokeConnection,
  updateScopes,
  verifyScopedAccess,
  recordBeaconPing,
  recordCheckIn,
  findUserBySafeId,
  VALID_SCOPES,
  VALID_MODES
};
