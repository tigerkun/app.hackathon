/**
 * SOS Auto-Escalation & Watchdog Test Suite (F3-1)
 *
 * Verifies:
 * 1. Time-shifted escalation levels 1, 2, 3 (capping at 3) with zero sleeps
 * 2. Immunity of resolved alerts against auto-escalation
 * 3. Watchdog timer lifecycle (start on trigger, stop on resolve all)
 * 4. Integration test: WebSocket broadcasts (SOS_ESCALATED and re-broadcast SOS_ALERT_BROADCAST)
 * 5. GET /api/v1/sos/active and GET /api/v1/sos/:id include escalationLevel and ageSeconds, never leaking tokens
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');

const { server, wss } = require('../src/server');
const { db } = require('../src/data/store');
const sosService = require('../src/services/sosService');
const { createAlert, toSafeAlert } = require('../src/models/alertModel');

describe('SOS Auto-Escalation & Watchdog Tests (F3-1)', () => {
  let baseUrl;
  let wsUrl;
  let testPort;

  before(async () => {
    process.env.NODE_ENV = 'test';
    // Boot composite server on ephemeral port (0)
    await new Promise((resolve, reject) => {
      server.listen(0, '127.0.0.1', (err) => {
        if (err) return reject(err);
        resolve();
      });
    });

    testPort = server.address().port;
    baseUrl = `http://127.0.0.1:${testPort}`;
    wsUrl = `ws://127.0.0.1:${testPort}/ws/sos`;
  });

  after(async () => {
    sosService.stopEscalationWatchdog();
    for (const client of wss.clients) {
      try { client.terminate(); } catch (_) {}
    }
    await new Promise((resolve) => {
      wss.close(() => {
        server.close(resolve);
      });
    });
  });

  beforeEach(() => {
    sosService.stopEscalationWatchdog();
    db.reset();
  });

  // Helper HTTP fetcher
  async function apiRequest(path, options = {}) {
    const url = `${baseUrl}${path}`;
    const headers = {
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    const res = await fetch(url, {
      method: options.method || 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined
    });
    let body = null;
    try {
      body = await res.json();
    } catch (_) {
      body = null;
    }
    return {
      status: res.status,
      headers: res.headers,
      body
    };
  }

  // ===========================================================================
  // SECTION 1: Deterministic Zero-Sleep Unit Tests
  // ===========================================================================
  describe('1. Deterministic Zero-Sleep Escalation Ticks', () => {
    it('escalates alert sequentially across levels 1, 2, and 3, then caps at 3', () => {
      const t0 = 1700000000000;
      const alert = db.saveAlert(createAlert({
        userId: 'usr_unit_test',
        userName: 'Escalation Citizen',
        latitude: 28.6139,
        longitude: 77.2090,
        status: 'active',
        escalationLevel: 0,
        triggeredAt: new Date(t0).toISOString()
      }));

      const escalateAfterMs = 600000; // 10 minutes

      // Tick 0: At t0 + 5 minutes (elapsed 300,000ms < threshold 600,000ms)
      const res0 = sosService.tickEscalation({
        now: t0 + 300000,
        escalateAfterMs
      });
      assert.equal(res0.length, 0, 'Must not escalate before 10 minutes elapsed');
      assert.equal(db.findAlertById(alert.id).escalationLevel, 0);

      // Tick 1: At t0 + 10 minutes (elapsed 600,000ms >= 600,000ms * 1) -> Level 1
      const escalatedEvents1 = [];
      const broadcastAlerts1 = [];
      const res1 = sosService.tickEscalation({
        now: t0 + 600000,
        escalateAfterMs,
        broadcastEscalation: (evt) => escalatedEvents1.push(evt),
        broadcastAlert: (alt) => broadcastAlerts1.push(alt)
      });

      assert.equal(res1.length, 1);
      assert.equal(res1[0].id, alert.id);
      assert.equal(res1[0].escalationLevel, 1);
      assert.equal(db.findAlertById(alert.id).escalationLevel, 1);

      assert.equal(escalatedEvents1.length, 1);
      assert.equal(escalatedEvents1[0].alertId, alert.id);
      assert.equal(escalatedEvents1[0].level, 1);
      assert.equal(escalatedEvents1[0].elapsedMin, 10);

      assert.equal(broadcastAlerts1.length, 1);
      assert.equal(broadcastAlerts1[0].id, alert.id);
      assert.equal(broadcastAlerts1[0].escalationLevel, 1);

      // Tick 2: At t0 + 20 minutes (elapsed 1,200,000ms >= 600,000ms * 2) -> Level 2
      const res2 = sosService.tickEscalation({
        now: t0 + 1200000,
        escalateAfterMs
      });
      assert.equal(res2.length, 1);
      assert.equal(res2[0].escalationLevel, 2);
      assert.equal(db.findAlertById(alert.id).escalationLevel, 2);

      // Tick 3: At t0 + 30 minutes (elapsed 1,800,000ms >= 600,000ms * 3) -> Level 3
      const res3 = sosService.tickEscalation({
        now: t0 + 1800000,
        escalateAfterMs
      });
      assert.equal(res3.length, 1);
      assert.equal(res3[0].escalationLevel, 3);
      assert.equal(db.findAlertById(alert.id).escalationLevel, 3);

      // Tick 4: At t0 + 60 minutes (elapsed 3,600,000ms) -> Capped at 3, no further escalation
      const res4 = sosService.tickEscalation({
        now: t0 + 3600000,
        escalateAfterMs
      });
      assert.equal(res4.length, 0, 'Must not escalate past level 3 cap');
      assert.equal(db.findAlertById(alert.id).escalationLevel, 3, 'Level must remain 3');
    });

    it('ensures resolved alerts are immune to auto-escalation', () => {
      const t0 = 1700000000000;
      const alert = db.saveAlert(createAlert({
        userId: 'usr_resolved',
        userName: 'Resolved User',
        latitude: 28.6139,
        longitude: 77.2090,
        status: 'active',
        escalationLevel: 0,
        triggeredAt: new Date(t0).toISOString()
      }));

      // Resolve the alert immediately
      const resolved = sosService.resolveSos(alert.id, 'Resolved quickly by responder');
      assert.equal(resolved.status, 'resolved');

      // Tick 2 hours later
      const res = sosService.tickEscalation({
        now: t0 + 7200000,
        escalateAfterMs: 600000
      });

      assert.equal(res.length, 0, 'Resolved alerts must never be escalated');
      const inDb = db.findAlertById(alert.id);
      assert.equal(inDb.status, 'resolved');
      assert.equal(inDb.escalationLevel, 0);
    });

    it('manages watchdog timer lifecycle on trigger and resolve', () => {
      assert.equal(sosService.isEscalationWatchdogRunning(), false);

      // Triggering SOS starts watchdog timer
      const alert1 = sosService.triggerSos({
        latitude: 28.6139,
        longitude: 77.2090,
        userName: 'Lifecycle User 1'
      });
      assert.equal(sosService.isEscalationWatchdogRunning(), true);

      // Trigger a second alert; watchdog stays active
      const alert2 = sosService.triggerSos({
        latitude: 28.6140,
        longitude: 77.2091,
        userName: 'Lifecycle User 2'
      });
      assert.equal(sosService.isEscalationWatchdogRunning(), true);

      // Resolve first alert; remaining active alert keeps watchdog running
      sosService.resolveSos(alert1.id);
      assert.equal(sosService.isEscalationWatchdogRunning(), true);

      // Resolve second alert; active count becomes 0, watchdog stops
      sosService.resolveSos(alert2.id);
      assert.equal(sosService.isEscalationWatchdogRunning(), false);
    });
  });

  // ===========================================================================
  // SECTION 2: Integration Test with WebSocket Protocol
  // ===========================================================================
  describe('2. WebSocket Escalation & Alert Re-broadcast', () => {
    it('broadcasts SOS_ESCALATED and re-broadcasts SOS_ALERT_BROADCAST to connected monitors', async () => {
      // 1. Connect WebSocket monitor client
      const wsClient = new WebSocket(wsUrl);
      const incomingMessages = [];

      wsClient.on('message', (raw) => {
        try {
          incomingMessages.push(JSON.parse(raw.toString()));
        } catch (_) {}
      });

      await new Promise((resolve, reject) => {
        wsClient.on('open', resolve);
        wsClient.on('error', reject);
      });

      // Wait briefly for welcome packet
      for (let i = 0; i < 20; i++) {
        if (incomingMessages.some((m) => m.type === 'CONNECTION_ESTABLISHED')) break;
        await new Promise((r) => setTimeout(r, 10));
      }
      assert.ok(incomingMessages.some((m) => m.type === 'CONNECTION_ESTABLISHED'), 'Must receive CONNECTION_ESTABLISHED');

      // 2. Trigger SOS
      const triggerRes = await apiRequest('/api/v1/sos/trigger', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          userName: 'WS Escalation User'
        }
      });
      assert.equal(triggerRes.status, 201);
      const alertId = triggerRes.body.data.id;
      assert.ok(alertId);

      // Give event loop time to deliver initial broadcast
      for (let i = 0; i < 20; i++) {
        if (incomingMessages.some((m) => m.type === 'SOS_ALERT_BROADCAST' && m.data && m.data.id === alertId)) break;
        await new Promise((r) => setTimeout(r, 10));
      }
      assert.ok(
        incomingMessages.some((m) => m.type === 'SOS_ALERT_BROADCAST' && m.data && m.data.id === alertId),
        'Must receive initial SOS_ALERT_BROADCAST'
      );

      // Clear collected messages to isolate escalation tick
      incomingMessages.length = 0;

      // 3. Run escalation tick with time-shifted now
      const nowShifted = Date.now() + 650000; // 10m 50s in future
      sosService.tickEscalation({
        now: nowShifted,
        escalateAfterMs: 600000
      });

      // Wait for escalation messages
      for (let i = 0; i < 20; i++) {
        if (
          incomingMessages.some((m) => m.type === 'SOS_ESCALATED') &&
          incomingMessages.some((m) => m.type === 'SOS_ALERT_BROADCAST' && m.data && m.data.id === alertId)
        ) {
          break;
        }
        await new Promise((r) => setTimeout(r, 10));
      }

      // 4. Verify client received SOS_ESCALATED event
      const escalatedMsg = incomingMessages.find((m) => m.type === 'SOS_ESCALATED');
      assert.ok(escalatedMsg, `Client must receive SOS_ESCALATED message. Received: ${JSON.stringify(incomingMessages)}`);
      assert.equal(escalatedMsg.alertId, alertId);
      assert.equal(escalatedMsg.level, 1);
      assert.equal(typeof escalatedMsg.elapsedMin, 'number');
      assert.ok(escalatedMsg.elapsedMin >= 10);

      // 5. Verify client received re-broadcast SOS_ALERT_BROADCAST
      const rebroadcastMsg = incomingMessages.find(
        (m) => m.type === 'SOS_ALERT_BROADCAST' && m.data && m.data.id === alertId
      );
      assert.ok(rebroadcastMsg, 'Client must receive re-broadcast SOS_ALERT_BROADCAST message');
      assert.equal(rebroadcastMsg.data.escalationLevel, 1);

      // Clean up socket
      wsClient.terminate();
    });
  });

  // ===========================================================================
  // SECTION 3: HTTP API GET /api/v1/sos/active and /api/v1/sos/:id
  // ===========================================================================
  describe('3. SOS Endpoints EscalationLevel, AgeSeconds, and Token Masking', () => {
    it('returns escalationLevel and ageSeconds in GET /api/v1/sos/active without leaking tokens', async () => {
      // Trigger an alert
      const triggerRes = await apiRequest('/api/v1/sos/trigger', {
        method: 'POST',
        body: {
          latitude: 28.6139,
          longitude: 77.2090,
          userName: 'Active Check Citizen'
        }
      });
      assert.equal(triggerRes.status, 201);
      const alertId = triggerRes.body.data.id;

      // Check GET /api/v1/sos/active
      const activeRes = await apiRequest('/api/v1/sos/active');
      assert.equal(activeRes.status, 200);
      assert.equal(activeRes.body.success, true);
      assert.ok(Array.isArray(activeRes.body.data));

      const activeAlert = activeRes.body.data.find((a) => a.id === alertId);
      assert.ok(activeAlert, 'Triggered alert must be present in active alerts list');

      // Check fields
      assert.equal(typeof activeAlert.escalationLevel, 'number');
      assert.equal(activeAlert.escalationLevel, 0);
      assert.equal(typeof activeAlert.ageSeconds, 'number');
      assert.ok(activeAlert.ageSeconds >= 0);

      // Security check: Never expose tokens
      assert.equal(activeAlert.resolveTokenHash, undefined, 'Must not leak resolveTokenHash');
      assert.equal(activeAlert.resolveToken, undefined, 'Must not leak resolveToken');

      // Update escalationLevel in DB directly to simulate advanced state
      db.updateAlert(alertId, { escalationLevel: 2 });

      const activeRes2 = await apiRequest('/api/v1/sos/active');
      const activeAlert2 = activeRes2.body.data.find((a) => a.id === alertId);
      assert.equal(activeAlert2.escalationLevel, 2);

      // Check GET /api/v1/sos/:id
      const idRes = await apiRequest(`/api/v1/sos/${alertId}`);
      assert.equal(idRes.status, 200);
      assert.equal(idRes.body.success, true);
      assert.equal(idRes.body.data.id, alertId);
      assert.equal(idRes.body.data.escalationLevel, 2);
      assert.equal(typeof idRes.body.data.ageSeconds, 'number');
      assert.ok(idRes.body.data.ageSeconds >= 0);
      assert.equal(idRes.body.data.resolveTokenHash, undefined, 'Must not leak resolveTokenHash');
      assert.equal(idRes.body.data.resolveToken, undefined, 'Must not leak resolveToken');
    });
  });
});
