/**
 * SafeSphere DataStore - SQLite Repository
 * Backed by Node.js built-in `node:sqlite` (DatabaseSync).
 * Provides CRUD repositories for users, sessions, reports, markers, alerts, otps, and tracking sessions.
 * Preserves synchronous API signatures, shallow copies, and instant reset() for test isolation.
 */

const { DatabaseSync } = require('node:sqlite');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('../config');
const { getSeedData } = require('./seedData');
const { normalizeEmail, normalizePhone } = require('../models/userModel');

function hashToken(token) {
  if (!token) return null;
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

class DataStore {
  constructor(dbPath = null) {
    this.dbPath = dbPath || config.dbPath || path.resolve(__dirname, '../../data/safesphere.db');
    if (this.dbPath !== ':memory:') {
      fs.mkdirSync(path.dirname(this.dbPath), { recursive: true });
    }
    this.db = new DatabaseSync(this.dbPath);
    this.initSchema();
  }

  initSchema() {
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = NORMAL;
      PRAGMA foreign_keys = ON;
      PRAGMA busy_timeout = 5000;

      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'citizen',
        passwordHash TEXT NOT NULL,
        pin TEXT,
        pinHash TEXT,
        biometricToken TEXT,
        biometricsEnabled INTEGER NOT NULL DEFAULT 0,
        emergencyContacts TEXT NOT NULL DEFAULT '[]',
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
      CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
      CREATE INDEX IF NOT EXISTS idx_users_biometricToken ON users(biometricToken);

      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        refreshToken TEXT,
        refreshTokenHash TEXT,
        userAgent TEXT,
        ipAddress TEXT,
        expiresAt TEXT NOT NULL,
        isValid INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        lastUsedAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_sessions_userId ON sessions(userId);
      CREATE INDEX IF NOT EXISTS idx_sessions_refreshToken ON sessions(refreshToken);
      CREATE INDEX IF NOT EXISTS idx_sessions_refreshTokenHash ON sessions(refreshTokenHash);

      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        description TEXT NOT NULL,
        location TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        status TEXT NOT NULL,
        reportedBy TEXT,
        attachments TEXT NOT NULL DEFAULT '[]',
        photoUrl TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_reports_createdAt ON reports(createdAt);
      CREATE INDEX IF NOT EXISTS idx_reports_type ON reports(type);
      CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);

      CREATE TABLE IF NOT EXISTS markers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        address TEXT,
        note TEXT,
        isVerified INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'verified',
        verifiedBy TEXT,
        verifiedAt TEXT,
        createdAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_markers_location ON markers(latitude, longitude);
      CREATE INDEX IF NOT EXISTS idx_markers_category ON markers(category);

      CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        userName TEXT NOT NULL,
        userPhone TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        batteryLevel REAL,
        alertType TEXT NOT NULL,
        status TEXT NOT NULL,
        escalationLevel INTEGER NOT NULL DEFAULT 0,
        triggeredAt TEXT NOT NULL,
        resolvedAt TEXT,
        emergencyContactsNotified INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        resolveTokenHash TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_alerts_status_triggeredAt ON alerts(status, triggeredAt);
      CREATE INDEX IF NOT EXISTS idx_alerts_userId ON alerts(userId);

      CREATE TABLE IF NOT EXISTS otps (
        phone TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        purpose TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        expiresAt INTEGER NOT NULL,
        cooldownUntil INTEGER NOT NULL,
        createdAt INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS tracking_sessions (
        id TEXT PRIMARY KEY,
        userId TEXT,
        userName TEXT NOT NULL,
        token TEXT NOT NULL,
        status TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        expiresAt TEXT NOT NULL,
        endedAt TEXT,
        initialLocation TEXT NOT NULL,
        currentLocation TEXT NOT NULL,
        breadcrumbs TEXT NOT NULL DEFAULT '[]',
        metadata TEXT NOT NULL DEFAULT '{}',
        lastActivityAt TEXT,
        lastPingAt TEXT,
        checkInIntervalMin INTEGER,
        checkInDeadline TEXT,
        missedCheckIns INTEGER NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_tracking_token ON tracking_sessions(token);
      CREATE INDEX IF NOT EXISTS idx_tracking_status ON tracking_sessions(status);

      CREATE TABLE IF NOT EXISTS sos_messages (
        id TEXT PRIMARY KEY,
        alertId TEXT NOT NULL,
        senderRole TEXT NOT NULL,
        senderId TEXT,
        text TEXT NOT NULL,
        createdAt TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_sos_messages_alertId ON sos_messages(alertId, createdAt);
    `);

    try {
      this.db.exec("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'citizen'");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE reports ADD COLUMN photoUrl TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE markers ADD COLUMN status TEXT DEFAULT 'verified'");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE markers ADD COLUMN verifiedBy TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE markers ADD COLUMN verifiedAt TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE markers ADD COLUMN note TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE alerts ADD COLUMN resolveTokenHash TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE alerts ADD COLUMN escalationLevel INTEGER DEFAULT 0");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE tracking_sessions ADD COLUMN lastActivityAt TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE tracking_sessions ADD COLUMN lastPingAt TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE tracking_sessions ADD COLUMN checkInIntervalMin INTEGER");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE tracking_sessions ADD COLUMN checkInDeadline TEXT");
    } catch (_) {}
    try {
      this.db.exec("ALTER TABLE tracking_sessions ADD COLUMN missedCheckIns INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
  }

  // Backward compatibility getters for tests asserting collection.size
  get users() {
    const store = this;
    return {
      get size() {
        return store._count('users');
      }
    };
  }

  get sessions() {
    const store = this;
    return {
      get size() {
        return store._count('sessions');
      }
    };
  }

  get reports() {
    const store = this;
    return {
      get size() {
        return store._count('reports');
      }
    };
  }

  get markers() {
    const store = this;
    return {
      get size() {
        return store._count('markers');
      }
    };
  }

  get alerts() {
    const store = this;
    return {
      get size() {
        return store._count('alerts');
      }
    };
  }

  get otps() {
    const store = this;
    return {
      get size() {
        return store._count('otps');
      }
    };
  }

  get trackingSessions() {
    const store = this;
    return {
      get size() {
        return store._count('tracking_sessions');
      }
    };
  }

  get sosMessages() {
    const store = this;
    return {
      get size() {
        return store._count('sos_messages');
      }
    };
  }

  _count(table) {
    if (!this.db) return 0;
    const row = this.db.prepare(`SELECT COUNT(*) AS c FROM ${table}`).get();
    return row ? Number(row.c) : 0;
  }

  init() {
    this.reset();
  }

  reset(options = {}) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.exec(`
        DELETE FROM users;
        DELETE FROM sessions;
        DELETE FROM reports;
        DELETE FROM markers;
        DELETE FROM alerts;
        DELETE FROM otps;
        DELETE FROM tracking_sessions;
        DELETE FROM sos_messages;
      `);

      const seed = getSeedData();

      const shouldSeedDemo = (options && options.demoMode !== undefined)
        ? Boolean(options.demoMode)
        : Boolean(config.isDemoMode);

      if (seed.demoUser && shouldSeedDemo) {
        this.saveUser(seed.demoUser);
      }

      if (Array.isArray(seed.reports)) {
        for (const rep of seed.reports) {
          this.saveReport(rep);
        }
      }

      if (Array.isArray(seed.markers)) {
        for (const m of seed.markers) {
          this.saveMarker(m);
        }
      }

      this.db.exec('COMMIT');
    } catch (err) {
      try { this.db.exec('ROLLBACK'); } catch (_) {}
      throw err;
    }
  }

  close() {
    if (this.db) {
      try {
        this.db.close();
      } catch (_) {}
      this.db = null;
    }
  }

  // ==========================================
  // User Repository
  // ==========================================

  _formatUser(row) {
    if (!row) return null;
    let emergencyContacts = [];
    try {
      emergencyContacts = typeof row.emergencyContacts === 'string'
        ? JSON.parse(row.emergencyContacts)
        : (row.emergencyContacts || []);
    } catch (_) {
      emergencyContacts = [];
    }
    return {
      id: row.id,
      name: row.name,
      email: row.email,
      phone: row.phone,
      role: row.role || 'citizen',
      passwordHash: row.passwordHash,
      pin: row.pin ?? null,
      pinHash: row.pinHash ?? null,
      biometricToken: row.biometricToken ?? null,
      biometricsEnabled: Boolean(row.biometricsEnabled),
      emergencyContacts: Array.isArray(emergencyContacts) ? emergencyContacts.map((c) => ({ ...c })) : [],
      isActive: Boolean(row.isActive),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt
    };
  }

  findUserById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM users WHERE id = ? LIMIT 1').get(id);
    return this._formatUser(row);
  }

  findUserByEmail(email) {
    if (!email) return null;
    const normalized = normalizeEmail(email);
    const row = this.db.prepare('SELECT * FROM users WHERE LOWER(TRIM(email)) = ? LIMIT 1').get(normalized);
    return this._formatUser(row);
  }

  findUserByPhone(phone) {
    if (!phone) return null;
    const normalized = normalizePhone(phone);
    const row = this.db.prepare('SELECT * FROM users WHERE TRIM(phone) = ? LIMIT 1').get(normalized);
    return this._formatUser(row);
  }

  findUserByEmailOrPhone(query) {
    if (!query) return null;
    const trimmed = String(query).trim();
    const byEmail = this.findUserByEmail(trimmed);
    if (byEmail) return byEmail;
    return this.findUserByPhone(trimmed);
  }

  findUserByBiometricToken(token) {
    if (!token) return null;
    const row = this.db.prepare('SELECT * FROM users WHERE biometricsEnabled = 1 AND biometricToken = ? LIMIT 1').get(token);
    return this._formatUser(row);
  }

  saveUser(user) {
    if (!user || !user.id) throw new Error('User must have an ID');
    const updatedAt = new Date().toISOString();
    const emergencyContactsStr = typeof user.emergencyContacts === 'string'
      ? user.emergencyContacts
      : JSON.stringify(user.emergencyContacts || []);

    this.db.prepare(`
      INSERT INTO users (
        id, name, email, phone, role, passwordHash, pin, pinHash, biometricToken,
        biometricsEnabled, emergencyContacts, isActive, createdAt, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        email = excluded.email,
        phone = excluded.phone,
        role = excluded.role,
        passwordHash = excluded.passwordHash,
        pin = excluded.pin,
        pinHash = excluded.pinHash,
        biometricToken = excluded.biometricToken,
        biometricsEnabled = excluded.biometricsEnabled,
        emergencyContacts = excluded.emergencyContacts,
        isActive = excluded.isActive,
        createdAt = excluded.createdAt,
        updatedAt = excluded.updatedAt
    `).run(
      user.id,
      user.name ?? '',
      user.email ?? '',
      user.phone ?? '',
      user.role || 'citizen',
      user.passwordHash ?? '',
      user.pin ?? null,
      user.pinHash ?? null,
      user.biometricToken ?? null,
      user.biometricsEnabled ? 1 : 0,
      emergencyContactsStr,
      user.isActive !== undefined ? (user.isActive ? 1 : 0) : 1,
      user.createdAt || new Date().toISOString(),
      updatedAt
    );

    return this.findUserById(user.id);
  }

  updateUser(id, updates) {
    const existing = this.findUserById(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id,
      updatedAt: new Date().toISOString()
    };
    return this.saveUser(updated);
  }

  deleteUser(id) {
    if (!id) return false;
    this.db.prepare('DELETE FROM sessions WHERE userId = ?').run(id);
    this.db.prepare('DELETE FROM sos_messages WHERE senderId = ? OR alertId IN (SELECT id FROM alerts WHERE userId = ?)').run(id, id);
    this.db.prepare('DELETE FROM alerts WHERE userId = ?').run(id);
    this.db.prepare('DELETE FROM tracking_sessions WHERE userId = ?').run(id);
    const res = this.db.prepare('DELETE FROM users WHERE id = ?').run(id);
    return res.changes > 0;
  }

  getAllUsers() {
    const rows = this.db.prepare('SELECT * FROM users').all();
    return rows.map((r) => this._formatUser(r));
  }

  // ==========================================
  // Session Repository
  // ==========================================

  _formatSession(row) {
    if (!row) return null;
    return {
      id: row.id,
      userId: row.userId,
      refreshToken: row.refreshToken ?? null,
      refreshTokenHash: row.refreshTokenHash ?? null,
      userAgent: row.userAgent ?? null,
      ipAddress: row.ipAddress ?? null,
      expiresAt: row.expiresAt,
      isValid: Boolean(row.isValid),
      createdAt: row.createdAt,
      lastUsedAt: row.lastUsedAt
    };
  }

  findSessionById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM sessions WHERE id = ? LIMIT 1').get(id);
    return this._formatSession(row);
  }

  findSessionsByUserId(userId) {
    if (!userId) return [];
    const rows = this.db.prepare('SELECT * FROM sessions WHERE userId = ?').all(userId);
    return rows.map((r) => this._formatSession(r));
  }

  findSessionByRefreshToken(refreshToken) {
    if (!refreshToken) return null;
    const hash = hashToken(refreshToken);
    let row = this.db.prepare('SELECT * FROM sessions WHERE refreshTokenHash = ? LIMIT 1').get(hash);
    if (!row) {
      row = this.db.prepare('SELECT * FROM sessions WHERE refreshToken = ? LIMIT 1').get(refreshToken);
      if (row && !row.refreshTokenHash) {
        this.db.prepare('UPDATE sessions SET refreshTokenHash = ? WHERE id = ?').run(hash, row.id);
        row.refreshTokenHash = hash;
      }
    }
    return this._formatSession(row);
  }

  saveSession(session) {
    if (!session || !session.id) throw new Error('Session must have an ID');
    const refreshToken = session.refreshToken ?? null;
    const refreshTokenHash = session.refreshTokenHash || (refreshToken ? hashToken(refreshToken) : null);

    this.db.prepare(`
      INSERT INTO sessions (
        id, userId, refreshToken, refreshTokenHash, userAgent, ipAddress,
        expiresAt, isValid, createdAt, lastUsedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        userId = excluded.userId,
        refreshToken = excluded.refreshToken,
        refreshTokenHash = excluded.refreshTokenHash,
        userAgent = excluded.userAgent,
        ipAddress = excluded.ipAddress,
        expiresAt = excluded.expiresAt,
        isValid = excluded.isValid,
        createdAt = excluded.createdAt,
        lastUsedAt = excluded.lastUsedAt
    `).run(
      session.id,
      session.userId ?? '',
      refreshToken,
      refreshTokenHash,
      session.userAgent ?? null,
      session.ipAddress ?? null,
      session.expiresAt || new Date().toISOString(),
      session.isValid !== undefined ? (session.isValid ? 1 : 0) : 1,
      session.createdAt || new Date().toISOString(),
      session.lastUsedAt || new Date().toISOString()
    );

    return this.findSessionById(session.id);
  }

  updateSession(id, updates) {
    const existing = this.findSessionById(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id
    };
    if (updates.refreshToken !== undefined) {
      updated.refreshTokenHash = updates.refreshToken ? hashToken(updates.refreshToken) : null;
    }
    return this.saveSession(updated);
  }

  invalidateSession(id) {
    if (!id) return false;
    const now = new Date().toISOString();
    const res = this.db.prepare('UPDATE sessions SET isValid = 0, lastUsedAt = ? WHERE id = ?').run(now, id);
    return res.changes > 0;
  }

  invalidateUserSessions(userId) {
    if (!userId) return 0;
    const res = this.db.prepare('UPDATE sessions SET isValid = 0 WHERE userId = ?').run(userId);
    return res.changes;
  }

  // ==========================================
  // Incident Report Repository
  // ==========================================

  _formatReport(row) {
    if (!row) return null;
    let attachments = [];
    try {
      attachments = typeof row.attachments === 'string'
        ? JSON.parse(row.attachments)
        : (row.attachments || []);
    } catch (_) {
      attachments = [];
    }
    return {
      id: row.id,
      type: row.type,
      description: row.description,
      location: row.location,
      latitude: row.latitude !== null && row.latitude !== undefined ? Number(row.latitude) : null,
      longitude: row.longitude !== null && row.longitude !== undefined ? Number(row.longitude) : null,
      status: row.status,
      reportedBy: row.reportedBy ?? null,
      attachments: Array.isArray(attachments) ? attachments.map((a) => (typeof a === 'object' && a !== null ? { ...a } : a)) : [],
      photoUrl: row.photoUrl ?? null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt
    };
  }

  findReportById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM reports WHERE id = ? LIMIT 1').get(id);
    return this._formatReport(row);
  }

  getAllReports(filter = {}) {
    const conditions = [];
    const params = [];
    if (filter.type) {
      conditions.push('type = ?');
      params.push(filter.type);
    }
    if (filter.status) {
      conditions.push('status = ?');
      params.push(filter.status);
    } else if (!filter.includeRejected) {
      conditions.push("(status != 'rejected' OR status IS NULL)");
    }
    if (filter.reportedBy) {
      conditions.push('reportedBy = ?');
      params.push(filter.reportedBy);
    }
    let sql = 'SELECT * FROM reports';
    if (conditions.length > 0) {
      sql += ' WHERE ' + conditions.join(' AND ');
    }
    sql += ' ORDER BY createdAt DESC';
    if (filter.limit && Number(filter.limit) > 0) {
      const clampedLimit = Math.min(Math.max(1, parseInt(filter.limit, 10) || 100), 100);
      sql += ' LIMIT ?';
      params.push(clampedLimit);
    }
    const rows = this.db.prepare(sql).all(...params);
    return rows.map((r) => this._formatReport(r));
  }

  saveReport(report) {
    if (!report || !report.id) throw new Error('Report must have an ID');
    const updatedAt = new Date().toISOString();
    const attachmentsStr = typeof report.attachments === 'string'
      ? report.attachments
      : JSON.stringify(report.attachments || []);

    this.db.prepare(`
      INSERT INTO reports (
        id, type, description, location, latitude, longitude,
        status, reportedBy, attachments, photoUrl, createdAt, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        type = excluded.type,
        description = excluded.description,
        location = excluded.location,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        status = excluded.status,
        reportedBy = excluded.reportedBy,
        attachments = excluded.attachments,
        photoUrl = excluded.photoUrl,
        createdAt = excluded.createdAt,
        updatedAt = excluded.updatedAt
    `).run(
      report.id,
      report.type ?? '',
      report.description ?? '',
      report.location ?? '',
      report.latitude !== undefined && report.latitude !== null ? Number(report.latitude) : null,
      report.longitude !== undefined && report.longitude !== null ? Number(report.longitude) : null,
      report.status ?? 'pending',
      report.reportedBy ?? null,
      attachmentsStr,
      report.photoUrl ?? null,
      report.createdAt || new Date().toISOString(),
      updatedAt
    );

    return this.findReportById(report.id);
  }

  updateReport(id, updates) {
    const existing = this.findReportById(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id,
      updatedAt: new Date().toISOString()
    };
    return this.saveReport(updated);
  }

  // ==========================================
  // Safety Marker Repository
  // ==========================================

  _formatMarker(row) {
    if (!row) return null;
    return {
      id: row.id,
      name: row.name,
      category: row.category,
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      address: row.address ?? null,
      note: row.note ?? null,
      isVerified: Boolean(row.isVerified),
      status: row.status || (Boolean(row.isVerified) ? 'verified' : 'pending'),
      verifiedBy: row.verifiedBy ?? null,
      verifiedAt: row.verifiedAt ?? null,
      createdAt: row.createdAt
    };
  }

  findMarkerById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM markers WHERE id = ? LIMIT 1').get(id);
    return this._formatMarker(row);
  }

  getAllMarkers(filter = {}) {
    const conditions = [];
    const params = [];
    if (filter.category) {
      conditions.push('category = ?');
      params.push(filter.category);
    }
    if (filter.isVerified !== undefined) {
      conditions.push('isVerified = ?');
      params.push(Boolean(filter.isVerified) ? 1 : 0);
    }
    if (filter.status) {
      conditions.push('status = ?');
      params.push(filter.status);
    } else if (!filter.includeRejected) {
      conditions.push("(status != 'rejected' OR status IS NULL)");
    }
    // Public marker lists must only expose verified markers — pending
    // community submissions stay in the privileged review queue unless the
    // caller explicitly filters or is privileged (includeUnverified).
    if (!filter.status && filter.isVerified === undefined && !filter.includeUnverified) {
      conditions.push("(status = 'verified' OR (status IS NULL AND isVerified = 1))");
    }
    let sql = 'SELECT * FROM markers';
    if (conditions.length > 0) {
      sql += ' WHERE ' + conditions.join(' AND ');
    }
    if (filter.limit !== undefined) {
      const limitVal = Math.min(Math.max(1, parseInt(filter.limit, 10) || 100), 100);
      sql += ' LIMIT ?';
      params.push(limitVal);
    }
    const rows = this.db.prepare(sql).all(...params);
    return rows.map((r) => this._formatMarker(r));
  }

  getPendingMarkers() {
    const rows = this.db.prepare(
      "SELECT * FROM markers WHERE status = 'pending' OR (status IS NULL AND isVerified = 0) ORDER BY createdAt DESC"
    ).all();
    return rows.map((r) => this._formatMarker(r));
  }

  verifyMarker(id, { approve = true, verifiedBy = null } = {}) {
    const marker = this.findMarkerById(id);
    if (!marker) return null;

    const isVerified = approve ? 1 : 0;
    const status = approve ? 'verified' : 'rejected';
    const verifiedAt = new Date().toISOString();

    this.db.prepare(`
      UPDATE markers
      SET isVerified = ?, status = ?, verifiedBy = ?, verifiedAt = ?
      WHERE id = ?
    `).run(isVerified, status, verifiedBy ? String(verifiedBy) : null, verifiedAt, id);

    return this.findMarkerById(id);
  }

  saveMarker(marker) {
    if (!marker || !marker.id) throw new Error('Marker must have an ID');
    const isVerified = marker.isVerified !== undefined ? (marker.isVerified ? 1 : 0) : 1;
    const status = marker.status || (isVerified ? 'verified' : 'pending');
    this.db.prepare(`
      INSERT INTO markers (
        id, name, category, latitude, longitude, address, note, isVerified, status, verifiedBy, verifiedAt, createdAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        category = excluded.category,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        address = excluded.address,
        note = excluded.note,
        isVerified = excluded.isVerified,
        status = excluded.status,
        verifiedBy = excluded.verifiedBy,
        verifiedAt = excluded.verifiedAt,
        createdAt = excluded.createdAt
    `).run(
      marker.id,
      marker.name ?? '',
      marker.category ?? '',
      Number(marker.latitude),
      Number(marker.longitude),
      marker.address ?? null,
      marker.note ?? null,
      isVerified,
      status,
      marker.verifiedBy ?? null,
      marker.verifiedAt ?? null,
      marker.createdAt || new Date().toISOString()
    );

    return this.findMarkerById(marker.id);
  }

  // ==========================================
  // SOS Alert Repository
  // ==========================================

  _formatAlert(row) {
    if (!row) return null;
    return {
      id: row.id,
      userId: row.userId,
      userName: row.userName,
      userPhone: row.userPhone ?? null,
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      accuracy: row.accuracy !== null && row.accuracy !== undefined ? Number(row.accuracy) : null,
      batteryLevel: row.batteryLevel !== null && row.batteryLevel !== undefined ? Number(row.batteryLevel) : null,
      alertType: row.alertType,
      status: row.status,
      escalationLevel: row.escalationLevel !== null && row.escalationLevel !== undefined ? Number(row.escalationLevel) : 0,
      triggeredAt: row.triggeredAt,
      resolvedAt: row.resolvedAt ?? null,
      emergencyContactsNotified: Boolean(row.emergencyContactsNotified),
      notes: row.notes ?? null,
      resolveTokenHash: row.resolveTokenHash ?? null
    };
  }

  findAlertById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM alerts WHERE id = ? LIMIT 1').get(id);
    return this._formatAlert(row);
  }

  getActiveAlerts() {
    const rows = this.db.prepare("SELECT * FROM alerts WHERE status = 'active' ORDER BY triggeredAt DESC").all();
    return rows.map((r) => this._formatAlert(r));
  }

  getAllAlerts() {
    const rows = this.db.prepare('SELECT * FROM alerts ORDER BY triggeredAt DESC').all();
    return rows.map((r) => this._formatAlert(r));
  }

  saveAlert(alert) {
    if (!alert || !alert.id) throw new Error('Alert must have an ID');
    this.db.prepare(`
      INSERT INTO alerts (
        id, userId, userName, userPhone, latitude, longitude, accuracy,
        batteryLevel, alertType, status, escalationLevel, triggeredAt, resolvedAt,
        emergencyContactsNotified, notes, resolveTokenHash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        userId = excluded.userId,
        userName = excluded.userName,
        userPhone = excluded.userPhone,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        accuracy = excluded.accuracy,
        batteryLevel = excluded.batteryLevel,
        alertType = excluded.alertType,
        status = excluded.status,
        escalationLevel = excluded.escalationLevel,
        triggeredAt = excluded.triggeredAt,
        resolvedAt = excluded.resolvedAt,
        emergencyContactsNotified = excluded.emergencyContactsNotified,
        notes = excluded.notes,
        resolveTokenHash = excluded.resolveTokenHash
    `).run(
      alert.id,
      alert.userId ?? '',
      alert.userName ?? '',
      alert.userPhone ?? null,
      Number(alert.latitude),
      Number(alert.longitude),
      alert.accuracy !== undefined && alert.accuracy !== null ? Number(alert.accuracy) : null,
      alert.batteryLevel !== undefined && alert.batteryLevel !== null ? Number(alert.batteryLevel) : null,
      alert.alertType ?? 'SOS',
      alert.status ?? 'active',
      alert.escalationLevel !== undefined && alert.escalationLevel !== null ? Number(alert.escalationLevel) : 0,
      alert.triggeredAt || new Date().toISOString(),
      alert.resolvedAt ?? null,
      alert.emergencyContactsNotified ? 1 : 0,
      alert.notes ?? null,
      alert.resolveTokenHash ?? null
    );

    return this.findAlertById(alert.id);
  }

  updateAlert(id, updates) {
    const existing = this.findAlertById(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id
    };
    return this.saveAlert(updated);
  }

  // ==========================================
  // OTP Repository
  // ==========================================

  _formatOtp(row) {
    if (!row) return null;
    return {
      phone: row.phone,
      code: row.code,
      purpose: row.purpose,
      attempts: Number(row.attempts),
      expiresAt: Number(row.expiresAt),
      cooldownUntil: Number(row.cooldownUntil),
      createdAt: Number(row.createdAt)
    };
  }

  getOtp(phone) {
    if (!phone) return null;
    const normalized = normalizePhone(phone);
    const row = this.db.prepare('SELECT * FROM otps WHERE phone = ? LIMIT 1').get(normalized);
    return this._formatOtp(row);
  }

  saveOtp(phone, otpRecord) {
    if (!phone) throw new Error('Phone is required for OTP');
    const normalized = normalizePhone(phone);
    this.db.prepare(`
      INSERT INTO otps (
        phone, code, purpose, attempts, expiresAt, cooldownUntil, createdAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(phone) DO UPDATE SET
        code = excluded.code,
        purpose = excluded.purpose,
        attempts = excluded.attempts,
        expiresAt = excluded.expiresAt,
        cooldownUntil = excluded.cooldownUntil,
        createdAt = excluded.createdAt
    `).run(
      normalized,
      String(otpRecord.code ?? ''),
      String(otpRecord.purpose ?? ''),
      Number(otpRecord.attempts ?? 0),
      Number(otpRecord.expiresAt ?? 0),
      Number(otpRecord.cooldownUntil ?? 0),
      Number(otpRecord.createdAt ?? 0)
    );

    return this.getOtp(normalized);
  }

  deleteOtp(phone) {
    if (!phone) return false;
    const normalized = normalizePhone(phone);
    const res = this.db.prepare('DELETE FROM otps WHERE phone = ?').run(normalized);
    return res.changes > 0;
  }

  // ==========================================
  // Live Tracking Session Repository
  // ==========================================

  _formatTrackingSession(row) {
    if (!row) return null;
    let initialLocation = {};
    let currentLocation = {};
    let breadcrumbs = [];
    let metadata = {};

    try {
      initialLocation = typeof row.initialLocation === 'string' ? JSON.parse(row.initialLocation) : (row.initialLocation || {});
    } catch (_) { initialLocation = {}; }

    try {
      currentLocation = typeof row.currentLocation === 'string' ? JSON.parse(row.currentLocation) : (row.currentLocation || {});
    } catch (_) { currentLocation = {}; }

    try {
      breadcrumbs = typeof row.breadcrumbs === 'string' ? JSON.parse(row.breadcrumbs) : (row.breadcrumbs || []);
    } catch (_) { breadcrumbs = []; }

    try {
      metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});
    } catch (_) { metadata = {}; }

    return {
      id: row.id,
      userId: row.userId ?? null,
      userName: row.userName,
      token: row.token,
      status: row.status,
      durationMinutes: Number(row.durationMinutes),
      createdAt: row.createdAt,
      expiresAt: row.expiresAt,
      endedAt: row.endedAt ?? null,
      initialLocation: { ...initialLocation },
      currentLocation: { ...currentLocation },
      breadcrumbs: Array.isArray(breadcrumbs) ? breadcrumbs.map((b) => ({ ...b })) : [],
      metadata: { ...metadata },
      lastActivityAt: row.lastActivityAt ?? null,
      lastPingAt: row.lastPingAt ?? null,
      checkInIntervalMin: row.checkInIntervalMin !== null && row.checkInIntervalMin !== undefined ? Number(row.checkInIntervalMin) : null,
      checkInDeadline: row.checkInDeadline ?? null,
      missedCheckIns: row.missedCheckIns !== null && row.missedCheckIns !== undefined ? Number(row.missedCheckIns) : 0,
      updatedAt: row.updatedAt
    };
  }

  findTrackingSessionById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM tracking_sessions WHERE id = ? LIMIT 1').get(id);
    if (!row) return null;

    let status = row.status;
    let updatedAt = row.updatedAt;
    if (status === 'active' && row.expiresAt && new Date(row.expiresAt) < new Date()) {
      status = 'expired';
      updatedAt = new Date().toISOString();
      this.db.prepare('UPDATE tracking_sessions SET status = ?, updatedAt = ? WHERE id = ?').run(status, updatedAt, id);
      row.status = status;
      row.updatedAt = updatedAt;
    }

    return this._formatTrackingSession(row);
  }

  saveTrackingSession(session) {
    if (!session || !session.id) throw new Error('Tracking session must have an ID');
    const updatedAt = new Date().toISOString();
    const initialLocationStr = typeof session.initialLocation === 'string'
      ? session.initialLocation
      : JSON.stringify(session.initialLocation || {});
    const currentLocationStr = typeof session.currentLocation === 'string'
      ? session.currentLocation
      : JSON.stringify(session.currentLocation || {});
    const breadcrumbsStr = typeof session.breadcrumbs === 'string'
      ? session.breadcrumbs
      : JSON.stringify(session.breadcrumbs || []);
    const metadataStr = typeof session.metadata === 'string'
      ? session.metadata
      : JSON.stringify(session.metadata || {});

    this.db.prepare(`
      INSERT INTO tracking_sessions (
        id, userId, userName, token, status, durationMinutes,
        createdAt, expiresAt, endedAt, initialLocation,
        currentLocation, breadcrumbs, metadata, lastActivityAt, lastPingAt,
        checkInIntervalMin, checkInDeadline, missedCheckIns, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        userId = excluded.userId,
        userName = excluded.userName,
        token = excluded.token,
        status = excluded.status,
        durationMinutes = excluded.durationMinutes,
        createdAt = excluded.createdAt,
        expiresAt = excluded.expiresAt,
        endedAt = excluded.endedAt,
        initialLocation = excluded.initialLocation,
        currentLocation = excluded.currentLocation,
        breadcrumbs = excluded.breadcrumbs,
        metadata = excluded.metadata,
        lastActivityAt = excluded.lastActivityAt,
        lastPingAt = excluded.lastPingAt,
        checkInIntervalMin = excluded.checkInIntervalMin,
        checkInDeadline = excluded.checkInDeadline,
        missedCheckIns = excluded.missedCheckIns,
        updatedAt = excluded.updatedAt
    `).run(
      session.id,
      session.userId ?? null,
      session.userName ?? '',
      session.token ?? '',
      session.status ?? 'active',
      Number(session.durationMinutes ?? 0),
      session.createdAt || new Date().toISOString(),
      session.expiresAt || new Date().toISOString(),
      session.endedAt ?? null,
      initialLocationStr,
      currentLocationStr,
      breadcrumbsStr,
      metadataStr,
      session.lastActivityAt ?? session.createdAt ?? new Date().toISOString(),
      session.lastPingAt ?? session.lastActivityAt ?? session.createdAt ?? new Date().toISOString(),
      session.checkInIntervalMin !== null && session.checkInIntervalMin !== undefined ? Number(session.checkInIntervalMin) : null,
      session.checkInDeadline ?? null,
      session.missedCheckIns !== null && session.missedCheckIns !== undefined ? Number(session.missedCheckIns) : 0,
      updatedAt
    );

    return this.findTrackingSessionById(session.id);
  }

  updateTrackingSession(id, updates) {
    const existing = this.findTrackingSessionById(id);
    if (!existing) return null;
    const updated = {
      ...existing,
      ...updates,
      id: existing.id,
      updatedAt: new Date().toISOString()
    };
    return this.saveTrackingSession(updated);
  }

  addTrackingBreadcrumb(id, breadcrumb) {
    const existing = this.findTrackingSessionById(id);
    if (!existing) return null;

    const point = {
      latitude: Number(breadcrumb.latitude),
      longitude: Number(breadcrumb.longitude),
      speed: breadcrumb.speed !== undefined && breadcrumb.speed !== null ? Number(breadcrumb.speed) : 0,
      battery: breadcrumb.battery !== undefined && breadcrumb.battery !== null ? Number(breadcrumb.battery) : null,
      accuracy: breadcrumb.accuracy !== undefined && breadcrumb.accuracy !== null ? Number(breadcrumb.accuracy) : null,
      timestamp: breadcrumb.timestamp || new Date().toISOString()
    };

    const breadcrumbs = Array.isArray(existing.breadcrumbs) ? existing.breadcrumbs : [];
    breadcrumbs.push(point);
    existing.breadcrumbs = breadcrumbs;
    existing.currentLocation = { ...point };
    const nowIso = new Date().toISOString();
    existing.lastActivityAt = nowIso;
    existing.lastPingAt = nowIso;
    if (existing.checkInIntervalMin) {
      existing.checkInDeadline = new Date(Date.now() + Number(existing.checkInIntervalMin) * 60 * 1000).toISOString();
      existing.missedCheckIns = 0;
    }
    existing.updatedAt = nowIso;

    return this.saveTrackingSession(existing);
  }

  getActiveCheckInSessions() {
    const rows = this.db.prepare(
      "SELECT * FROM tracking_sessions WHERE status = 'active' AND checkInIntervalMin IS NOT NULL AND checkInDeadline IS NOT NULL"
    ).all();
    const active = [];
    for (const row of rows) {
      if (row.expiresAt && new Date(row.expiresAt) < new Date()) {
        this.db.prepare("UPDATE tracking_sessions SET status = 'expired', updatedAt = ? WHERE id = ?").run(
          new Date().toISOString(),
          row.id
        );
        continue;
      }
      active.push(this._formatTrackingSession(row));
    }
    return active;
  }

  getAllTrackingSessions() {
    const rows = this.db.prepare('SELECT * FROM tracking_sessions').all();
    return rows.map((r) => this._formatTrackingSession(r));
  }

  // ==========================================
  // SOS Chat Message Repository
  // ==========================================

  _formatSosMessage(row) {
    if (!row) return null;
    return {
      id: row.id,
      alertId: row.alertId,
      senderRole: row.senderRole,
      senderId: row.senderId ?? null,
      text: row.text,
      createdAt: row.createdAt
    };
  }

  findSosMessageById(id) {
    if (!id) return null;
    const row = this.db.prepare('SELECT * FROM sos_messages WHERE id = ? LIMIT 1').get(id);
    return this._formatSosMessage(row);
  }

  saveSosMessage({ alertId, senderRole, senderId = null, text, createdAt = null }) {
    if (!alertId || !text) throw new Error('alertId and text are required');
    const id = `msg_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
    const timestamp = createdAt || new Date().toISOString();

    this.db.prepare(`
      INSERT INTO sos_messages (id, alertId, senderRole, senderId, text, createdAt)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, alertId, senderRole, senderId, String(text).trim(), timestamp);

    // Enforce FIFO cap: keep last 50 messages per alertId
    this.db.prepare(`
      DELETE FROM sos_messages
      WHERE alertId = ?
        AND id NOT IN (
          SELECT id FROM sos_messages
          WHERE alertId = ?
          ORDER BY createdAt DESC, id DESC
          LIMIT 50
        )
    `).run(alertId, alertId);

    return this.findSosMessageById(id);
  }

  getSosMessages(alertId, limit = 50) {
    if (!alertId) return [];
    const clampedLimit = Math.min(Math.max(1, parseInt(limit, 10) || 50), 50);
    const rows = this.db.prepare(`
      SELECT * FROM (
        SELECT * FROM sos_messages
        WHERE alertId = ?
        ORDER BY createdAt DESC, id DESC
        LIMIT ?
      ) ORDER BY createdAt ASC, id ASC
    `).all(alertId, clampedLimit);
    return rows.map((r) => this._formatSosMessage(r));
  }
}

// Global Singleton
const db = new DataStore();

module.exports = {
  DataStore,
  db
};
