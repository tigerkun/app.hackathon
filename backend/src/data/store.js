/**
 * DataStore - In-Memory Thread-Safe Repository
 * Provides CRUD repositories for users, sessions, reports, markers, alerts, and OTPs.
 * Supports zero-dependency boot in < 15ms and instant reset() for test isolation.
 */

const { getSeedData } = require('./seedData');
const { normalizeEmail, normalizePhone } = require('../models/userModel');

class DataStore {
  constructor() {
    this.users = new Map();
    this.sessions = new Map();
    this.reports = new Map();
    this.markers = new Map();
    this.alerts = new Map();
    this.otps = new Map();

    this.init();
  }

  init() {
    this.reset();
  }

  reset() {
    this.users.clear();
    this.sessions.clear();
    this.reports.clear();
    this.markers.clear();
    this.alerts.clear();
    this.otps.clear();

    const seed = getSeedData();

    // Seed Demo User
    if (seed.demoUser) {
      this.users.set(seed.demoUser.id, { ...seed.demoUser });
    }

    // Seed Reports
    if (Array.isArray(seed.reports)) {
      for (const rep of seed.reports) {
        this.reports.set(rep.id, { ...rep });
      }
    }

    // Seed Markers
    if (Array.isArray(seed.markers)) {
      for (const m of seed.markers) {
        this.markers.set(m.id, { ...m });
      }
    }
  }

  // ==========================================
  // User Repository
  // ==========================================

  findUserById(id) {
    if (!id) return null;
    const user = this.users.get(id);
    return user ? { ...user } : null;
  }

  findUserByEmail(email) {
    if (!email) return null;
    const normalized = normalizeEmail(email);
    for (const user of this.users.values()) {
      if (normalizeEmail(user.email) === normalized) {
        return { ...user };
      }
    }
    return null;
  }

  findUserByPhone(phone) {
    if (!phone) return null;
    const normalized = normalizePhone(phone);
    for (const user of this.users.values()) {
      if (normalizePhone(user.phone) === normalized) {
        return { ...user };
      }
    }
    return null;
  }

  findUserByEmailOrPhone(query) {
    if (!query) return null;
    const trimmed = String(query).trim();
    // Try email first
    const byEmail = this.findUserByEmail(trimmed);
    if (byEmail) return byEmail;
    // Try phone
    return this.findUserByPhone(trimmed);
  }

  findUserByBiometricToken(token) {
    if (!token) return null;
    for (const user of this.users.values()) {
      if (user.biometricsEnabled && user.biometricToken === token) {
        return { ...user };
      }
    }
    return null;
  }

  saveUser(user) {
    if (!user || !user.id) throw new Error('User must have an ID');
    const toSave = { ...user, updatedAt: new Date().toISOString() };
    this.users.set(user.id, toSave);
    return { ...toSave };
  }

  updateUser(id, updates) {
    const existing = this.users.get(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id, // ID cannot be updated
      updatedAt: new Date().toISOString()
    };
    this.users.set(id, updated);
    return { ...updated };
  }

  deleteUser(id) {
    return this.users.delete(id);
  }

  getAllUsers() {
    return Array.from(this.users.values()).map((u) => ({ ...u }));
  }

  // ==========================================
  // Session Repository
  // ==========================================

  findSessionById(id) {
    if (!id) return null;
    const session = this.sessions.get(id);
    return session ? { ...session } : null;
  }

  findSessionByRefreshToken(refreshToken) {
    if (!refreshToken) return null;
    for (const session of this.sessions.values()) {
      if (session.refreshToken === refreshToken) {
        return { ...session };
      }
    }
    return null;
  }

  saveSession(session) {
    if (!session || !session.id) throw new Error('Session must have an ID');
    this.sessions.set(session.id, { ...session });
    return { ...session };
  }

  updateSession(id, updates) {
    const existing = this.sessions.get(id);
    if (!existing) return null;
    const updated = { ...existing, ...updates, id: existing.id };
    this.sessions.set(id, updated);
    return { ...updated };
  }

  invalidateSession(id) {
    const existing = this.sessions.get(id);
    if (!existing) return false;
    existing.isValid = false;
    existing.lastUsedAt = new Date().toISOString();
    this.sessions.set(id, existing);
    return true;
  }

  invalidateUserSessions(userId) {
    let count = 0;
    for (const session of this.sessions.values()) {
      if (session.userId === userId) {
        session.isValid = false;
        count++;
      }
    }
    return count;
  }

  // ==========================================
  // Incident Report Repository
  // ==========================================

  findReportById(id) {
    if (!id) return null;
    const report = this.reports.get(id);
    return report ? { ...report } : null;
  }

  getAllReports(filter = {}) {
    let list = Array.from(this.reports.values());
    if (filter.type) {
      list = list.filter((r) => r.type === filter.type);
    }
    if (filter.status) {
      list = list.filter((r) => r.status === filter.status);
    }
    if (filter.reportedBy) {
      list = list.filter((r) => r.reportedBy === filter.reportedBy);
    }
    // Sort descending by creation date
    list.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    if (filter.limit && filter.limit > 0) {
      list = list.slice(0, filter.limit);
    }
    return list.map((r) => ({ ...r }));
  }

  saveReport(report) {
    if (!report || !report.id) throw new Error('Report must have an ID');
    const toSave = { ...report, updatedAt: new Date().toISOString() };
    this.reports.set(report.id, toSave);
    return { ...toSave };
  }

  updateReport(id, updates) {
    const existing = this.reports.get(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id,
      updatedAt: new Date().toISOString()
    };
    this.reports.set(id, updated);
    return { ...updated };
  }

  // ==========================================
  // Safety Marker Repository
  // ==========================================

  findMarkerById(id) {
    if (!id) return null;
    const marker = this.markers.get(id);
    return marker ? { ...marker } : null;
  }

  getAllMarkers(filter = {}) {
    let list = Array.from(this.markers.values());
    if (filter.category) {
      list = list.filter((m) => m.category === filter.category);
    }
    if (filter.isVerified !== undefined) {
      list = list.filter((m) => m.isVerified === Boolean(filter.isVerified));
    }
    return list.map((m) => ({ ...m }));
  }

  saveMarker(marker) {
    if (!marker || !marker.id) throw new Error('Marker must have an ID');
    this.markers.set(marker.id, { ...marker });
    return { ...marker };
  }

  // ==========================================
  // SOS Alert Repository
  // ==========================================

  findAlertById(id) {
    if (!id) return null;
    const alert = this.alerts.get(id);
    return alert ? { ...alert } : null;
  }

  getActiveAlerts() {
    return Array.from(this.alerts.values())
      .filter((a) => a.status === 'active')
      .sort((a, b) => new Date(b.triggeredAt) - new Date(a.triggeredAt))
      .map((a) => ({ ...a }));
  }

  getAllAlerts() {
    return Array.from(this.alerts.values())
      .sort((a, b) => new Date(b.triggeredAt) - new Date(a.triggeredAt))
      .map((a) => ({ ...a }));
  }

  saveAlert(alert) {
    if (!alert || !alert.id) throw new Error('Alert must have an ID');
    this.alerts.set(alert.id, { ...alert });
    return { ...alert };
  }

  updateAlert(id, updates) {
    const existing = this.alerts.get(id);
    if (!existing) return null;
    const updated = { ...existing, ...updates, id: existing.id };
    this.alerts.set(id, updated);
    return { ...updated };
  }

  // ==========================================
  // OTP Repository
  // ==========================================

  getOtp(phone) {
    if (!phone) return null;
    const normalized = normalizePhone(phone);
    const record = this.otps.get(normalized);
    return record ? { ...record } : null;
  }

  saveOtp(phone, otpRecord) {
    if (!phone) throw new Error('Phone is required for OTP');
    const normalized = normalizePhone(phone);
    this.otps.set(normalized, { ...otpRecord, phone: normalized });
    return { ...otpRecord, phone: normalized };
  }

  deleteOtp(phone) {
    if (!phone) return false;
    const normalized = normalizePhone(phone);
    return this.otps.delete(normalized);
  }
}

// Global Singleton
const db = new DataStore();

module.exports = {
  DataStore,
  db
};
