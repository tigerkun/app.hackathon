/**
 * SafeSphere Fixture Seeds
 * Pre-seeded demo user (demo@safesphere.org / SafeSphere@2026),
 * Delhi NCR safety markers, and community incident reports.
 */

const bcrypt = require('bcryptjs');
const config = require('../config');

// Precomputed bcrypt hash of "SafeSphere@2026" (rounds 8-10)
// Also fallback to hashSync dynamically if needed
const DEMO_PASSWORD = 'SafeSphere@2026';
let DEMO_PASSWORD_HASH = '$2a$10$wE96c1B6jLhyHkGqFkS9.e44wZ6q227uKxKzI3E7hL0dOqO.e7w7C';

try {
  // Ensure hash matches current salt rounds
  DEMO_PASSWORD_HASH = bcrypt.hashSync(DEMO_PASSWORD, config.saltRounds);
} catch (e) {
  // Fallback to precomputed valid bcrypt hash
}

function getSeedData() {
  const now = new Date().toISOString();

  const demoUser = {
    id: 'user_safesphere_demo_01',
    name: 'Jane SafeSphere',
    email: 'demo@safesphere.org',
    phone: '+91 9876543210',
    passwordHash: DEMO_PASSWORD_HASH,
    pin: '1234',
    biometricToken: 'bio_device_demo_token_xyz987',
    biometricsEnabled: true,
    emergencyContacts: [
      {
        id: 'cnt_01',
        name: 'Emergency Services',
        phone: '112',
        relationship: 'National Emergency'
      },
      {
        id: 'cnt_02',
        name: 'Family Contact',
        phone: '+91 9876500001',
        relationship: 'Mother'
      }
    ],
    isActive: true,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: now
  };

  const reports = [
    {
      id: 'rep_1001',
      type: 'Theft',
      description: 'Bicycle reported stolen near Sector 18 Metro station bike rack.',
      location: 'Sector 18 Metro, Gate 2',
      latitude: 28.5708,
      longitude: 77.3271,
      status: 'verified',
      reportedBy: demoUser.id,
      attachments: [],
      createdAt: '2026-04-10T14:30:00.000Z',
      updatedAt: '2026-04-10T15:00:00.000Z'
    },
    {
      id: 'rep_1002',
      type: 'Harassment',
      description: 'Poorly lit underpass with groups loitering late evening.',
      location: 'North Ridge Underpass',
      latitude: 28.6920,
      longitude: 77.2150,
      status: 'under_investigation',
      reportedBy: demoUser.id,
      attachments: [],
      createdAt: '2026-04-11T20:15:00.000Z',
      updatedAt: '2026-04-11T20:15:00.000Z'
    },
    {
      id: 'rep_1003',
      type: 'Accident',
      description: 'Minor two-wheeler collision, emergency medical team dispatched.',
      location: 'Outer Ring Road Junction',
      latitude: 28.6289,
      longitude: 77.2065,
      status: 'resolved',
      reportedBy: demoUser.id,
      attachments: [],
      createdAt: '2026-04-12T08:45:00.000Z',
      updatedAt: '2026-04-12T09:30:00.000Z'
    }
  ];

  const markers = [
    {
      id: 'marker_police_cp',
      name: 'Connaught Place Central Police Post',
      category: 'Police Station',
      latitude: 28.6315,
      longitude: 77.2167,
      address: 'Inner Circle, Connaught Place, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_hospital_aiims',
      name: 'AIIMS Emergency Trauma Care',
      category: 'Hospital',
      latitude: 28.5672,
      longitude: 77.2100,
      address: 'Ansari Nagar, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_safe_delhi_hub',
      name: '24/7 Women Transit Helpdesk & Safe Zone',
      category: 'Verified Safe Zone',
      latitude: 28.6139,
      longitude: 77.2090,
      address: 'Central Secretariat Metro, Gate 1',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    }
  ];

  return {
    demoUser,
    reports,
    markers
  };
}

module.exports = {
  getSeedData,
  DEMO_PASSWORD,
  DEMO_PASSWORD_HASH
};
