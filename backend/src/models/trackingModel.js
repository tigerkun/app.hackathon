/**
 * Live Tracking Session Entity Model
 * Schema and factory for real-time live guardian tracking breadcrumbs.
 */

const crypto = require('crypto');

function generateTrackingSessionId() {
  return `trk_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
}

function generateTrackingToken() {
  return crypto.randomBytes(16).toString('hex');
}

const VALID_TRACKING_STATUSES = ['active', 'ended', 'expired'];

function createTrackingSession({
  id = generateTrackingSessionId(),
  userId = null,
  userName = 'SafeSphere Citizen',
  latitude,
  longitude,
  accuracy = null,
  speed = 0,
  battery = null,
  durationMinutes = 60,
  token = generateTrackingToken(),
  status = 'active',
  createdAt = new Date().toISOString(),
  lastActivityAt = null,
  lastPingAt = null,
  expiresAt = null,
  endedAt = null,
  metadata = {}
}) {
  const parsedLat = Number(latitude);
  const parsedLng = Number(longitude);
  const parsedAccuracy = accuracy !== null && accuracy !== undefined ? Number(accuracy) : null;
  const parsedSpeed = speed !== null && speed !== undefined ? Number(speed) : 0;
  const parsedBattery = battery !== null && battery !== undefined ? Number(battery) : null;

  const expirationDate = expiresAt || new Date(Date.now() + Number(durationMinutes || 60) * 60 * 1000).toISOString();

  const initialPoint = {
    latitude: parsedLat,
    longitude: parsedLng,
    accuracy: parsedAccuracy,
    speed: parsedSpeed,
    battery: parsedBattery,
    timestamp: createdAt
  };

  return {
    id,
    userId: userId ? String(userId) : null,
    userName: String(userName || 'SafeSphere Citizen'),
    token,
    status: VALID_TRACKING_STATUSES.includes(status) ? status : 'active',
    durationMinutes: Number(durationMinutes || 60),
    createdAt,
    lastActivityAt: lastActivityAt || createdAt,
    lastPingAt: lastPingAt || createdAt,
    expiresAt: expirationDate,
    endedAt: endedAt ? String(endedAt) : null,
    initialLocation: { ...initialPoint },
    currentLocation: { ...initialPoint },
    breadcrumbs: [{ ...initialPoint }],
    metadata: { ...metadata }
  };
}

module.exports = {
  createTrackingSession,
  generateTrackingSessionId,
  generateTrackingToken,
  VALID_TRACKING_STATUSES
};
