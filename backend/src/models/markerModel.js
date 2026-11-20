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
    isVerified: verifiedBool,
    status: status || (verifiedBool ? 'verified' : 'pending'),
    verifiedBy: verifiedBy ? String(verifiedBy) : null,
    verifiedAt: verifiedAt ? String(verifiedAt) : null,
    createdAt
  };
}

module.exports = {
  createMarker,
  generateMarkerId,
  VALID_MARKER_CATEGORIES
};
