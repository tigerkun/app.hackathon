/**
 * Safety Marker Entity Model
 * SafeSphere verified safety infrastructure and resource pin schema.
 */

const crypto = require('crypto');

function generateMarkerId() {
  return `marker_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_MARKER_CATEGORIES = [
  'Police Station',
  'Hospital',
  'Verified Safe Zone',
  'Well-lit Transit Hub',
  'Caution Area'
];

function createMarker({
  id = generateMarkerId(),
  name,
  category = 'Verified Safe Zone',
  latitude,
  longitude,
  address = null,
  note = null,
  isVerified = false,
  status = null,
  verifiedBy = null,
  verifiedAt = null,
  createdAt = new Date().toISOString()
}) {
  const verifiedBool = Boolean(isVerified);
  return {
    id,
    name: (name || '').trim(),
    category: VALID_MARKER_CATEGORIES.includes(category) ? category : 'Verified Safe Zone',
    latitude: Number(latitude),
    longitude: Number(longitude),
    address: address ? String(address).trim() : null,
    note: note ? String(note).trim().slice(0, 500) : null,
    isVerified: verifiedBool,
    status: status || (verifiedBool ? 'verified' : 'pending'),
    verifiedBy: verifiedBy ? String(verifiedBy) : null,
    verifiedAt: verifiedAt ? String(verifiedAt) : null,
    createdAt
  };
}

function toSafeMarker(marker, isPrivileged = false) {
  if (!marker) return null;
  return {
    id: marker.id,
    name: marker.name,
    category: marker.category,
    latitude: marker.latitude,
    longitude: marker.longitude,
    address: marker.address ?? null,
    // Moderator notes are for reviewers only — never exposed publicly.
    note: isPrivileged ? (marker.note ?? null) : undefined,
    isVerified: Boolean(marker.isVerified),
    status: marker.status || (marker.isVerified ? 'verified' : 'pending'),
    verifiedBy: isPrivileged ? (marker.verifiedBy ?? null) : undefined,
    verifiedAt: marker.verifiedAt ?? null,
    createdAt: marker.createdAt,
    ...(marker.distanceKm !== undefined ? { distanceKm: marker.distanceKm } : {})
  };
}

module.exports = {
  createMarker,
  toSafeMarker,
  generateMarkerId,
  VALID_MARKER_CATEGORIES
};
