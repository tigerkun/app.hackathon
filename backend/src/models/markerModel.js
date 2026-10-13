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
  isVerified = true,
  createdAt = new Date().toISOString()
}) {
  return {
    id,
    name: (name || '').trim(),
    category: VALID_MARKER_CATEGORIES.includes(category) ? category : 'Verified Safe Zone',
    latitude: Number(latitude),
    longitude: Number(longitude),
    address: address ? String(address).trim() : null,
    isVerified: Boolean(isVerified),
    createdAt
  };
}

module.exports = {
  createMarker,
  generateMarkerId,
  VALID_MARKER_CATEGORIES
};
