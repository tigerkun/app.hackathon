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

const DEMO_PIN = '1234';
let DEMO_PIN_HASH = '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy';

try {
  DEMO_PIN_HASH = bcrypt.hashSync(DEMO_PIN, config.saltRounds);
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
    phoneVerified: true,
    passwordHash: DEMO_PASSWORD_HASH,
    pin: DEMO_PIN_HASH,
    pinHash: DEMO_PIN_HASH,
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
      // Freshness-relative timestamps: unverified statuses expire 24h after
      // creation, so fixed calendar dates would silently archive the demo feed.
      createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
      updatedAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString()
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
    },
    {
      id: 'marker_store_cp_247',
      name: 'Apollo 24x7 Emergency Chemist & Safe Store',
      category: '24x7 Store',
      latitude: 28.6322,
      longitude: 77.2185,
      address: 'Block E, Inner Circle, Connaught Place, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_store_delhi_24seven',
      name: '24 Seven Lit Convenience & Safe Refuge',
      category: '24x7 Store',
      latitude: 28.6295,
      longitude: 77.2152,
      address: 'Regal Building, Connaught Circus, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_police_hauz_khas',
      name: 'Hauz Khas Police Station',
      category: 'Police Station',
      latitude: 28.5494,
      longitude: 77.2001,
      address: 'Aurobindo Marg, Hauz Khas, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_hospital_safdarjung',
      name: 'Safdarjung Hospital Emergency Services',
      category: 'Hospital',
      latitude: 28.5695,
      longitude: 77.2075,
      address: 'Ring Road, Opposite AIIMS, New Delhi',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_safe_noida_hub',
      name: 'Sector 18 Metro Safe Women Helpdesk',
      category: 'Verified Safe Zone',
      latitude: 28.5708,
      longitude: 77.3271,
      address: 'Sector 18 Metro Gate 2, Noida',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_store_noida_247',
      name: 'Guardian 24x7 Chemist & Safe Haven',
      category: '24x7 Store',
      latitude: 28.5715,
      longitude: 77.3260,
      address: 'Atta Market, Sector 18, Noida',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_police_blr_indiranagar',
      name: 'Indiranagar Police Station',
      category: 'Police Station',
      latitude: 12.9784,
      longitude: 77.6408,
      address: '100 Feet Rd, Indiranagar, Bengaluru',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_hospital_blr_manipal',
      name: 'Manipal Hospital Emergency & Trauma Care',
      category: 'Hospital',
      latitude: 12.9584,
      longitude: 77.6489,
      address: '98 HAL Old Airport Rd, Kodihalli, Bengaluru',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_store_blr_247',
      name: 'MedPlus 24x7 Pharmacy & Lit Safe Refuge',
      category: '24x7 Store',
      latitude: 12.9716,
      longitude: 77.6412,
      address: '12th Main Rd, Indiranagar, Bengaluru',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_safe_blr_hub',
      name: 'Koramangala Safe Transit Zone & Kiosk',
      category: 'Verified Safe Zone',
      latitude: 12.9352,
      longitude: 77.6245,
      address: '80 Feet Road, Koramangala 4th Block, Bengaluru',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_police_mum_bandra',
      name: 'Bandra Police Station',
      category: 'Police Station',
      latitude: 19.0553,
      longitude: 72.8335,
      address: 'Hill Road, Bandra West, Mumbai',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_hospital_mum_lilavati',
      name: 'Lilavati Hospital & Emergency Care',
      category: 'Hospital',
      latitude: 19.0515,
      longitude: 72.8291,
      address: 'A-791 Bandra Reclamation, Mumbai',
      isVerified: true,
      createdAt: '2026-01-01T00:00:00.000Z'
    },
    {
      id: 'marker_store_mum_wellness',
      name: 'Wellness Forever 24x7 Safe Refuge',
      category: '24x7 Store',
      latitude: 19.0596,
      longitude: 72.8295,
      address: 'Turner Road, Bandra West, Mumbai',
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
  DEMO_PASSWORD_HASH,
  DEMO_PIN,
  DEMO_PIN_HASH
};
