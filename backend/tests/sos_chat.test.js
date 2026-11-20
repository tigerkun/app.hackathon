/**
 * Two-Way SOS Responder Chat Test Suite (F4-1)
 *
 * Verifies:
 * 1. REST: POST /api/v1/sos/:id/messages (victim with resolveToken, victim with JWT, responder with JWT)
 * 2. REST: Auth gating (401/403 on missing or invalid tokens)
 * 3. REST: Text validation (1-500 characters, rejects empty or oversized)
 * 4. REST: Rate-limiting (max 1 msg/2s per sender returns 429)
 * 5. REST: GET /api/v1/sos/:id/messages (authorized retrieval, token gating)
 * 6. FIFO Cap: Persists last 50 messages per alert in SQLite
 * 7. WebSocket: CHAT_MESSAGE frame handling, authentication, rate-limiting, and real broadcast
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');

const { server, wss } = require('../src/server');
const { db } = require('../src/data/store');
const sosService = require('../src/services/sosService');
const tokenService = require('../src/services/tokenService');
const { createUser } = require('../src/models/userModel');

describe('Two-Way SOS Responder Chat Tests (F4-1)', () => {
  let baseUrl;
  let wsUrl;
  let testPort;

  before(async () => {
    process.env.NODE_ENV = 'test';
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
    sosService.resetChatRateLimits();
    db.reset();
  });

  async function apiRequest(path, options = {}) {
    const url = `${baseUrl}${path}`;
    const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
    const fetchOptions = {
      method: options.method || 'GET',
      headers,
    };
    if (options.body) {
      fetchOptions.body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
    }
    const res = await fetch(url, fetchOptions);
    let json = null;
    try {
      json = await res.json();
    } catch (_) {}
    return { status: res.status, headers: res.headers, data: json };
  }

  it('1. POST /api/v1/sos/:id/messages allows victim with resolveToken to send message', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS',
      notes: 'Need assistance'
    });

    assert.ok(alert.resolveToken, 'resolveToken should be returned on trigger');

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: {
        token: alert.resolveToken,
        text: 'I am hiding behind the counter, 2 suspects outside.'
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.data.success, true);
    assert.equal(res.data.data.alertId, alert.id);
    assert.equal(res.data.data.senderRole, 'victim');
    assert.equal(res.data.data.text, 'I am hiding behind the counter, 2 suspects outside.');
    assert.ok(res.data.data.id);
    assert.ok(res.data.data.createdAt);
  });

  it('2. POST /api/v1/sos/:id/messages allows responder with JWT to send message', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // Create responder user & token
    const responderUser = db.saveUser(createUser({
      id: 'usr_responder_1',
      name: 'Officer John',
      email: 'responder@safesphere.test',
      phone: '+919876543210',
      role: 'first_responder'
    }));

    const responderToken = tokenService.signAccessToken(responderUser, 'ses_responder_1');

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${responderToken}` },
      body: {
        text: 'Unit 4 dispatched, ETA 3 minutes. Stay low.'
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.data.success, true);
    assert.equal(res.data.data.senderRole, 'responder');
    assert.equal(res.data.data.senderId, 'usr_responder_1');
    assert.equal(res.data.data.text, 'Unit 4 dispatched, ETA 3 minutes. Stay low.');
  });

  it('3. POST /api/v1/sos/:id/messages rejects unauthorized callers without token or JWT', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { text: 'Hello?' }
    });

    assert.equal(res.status, 401);
    assert.equal(res.data.success, false);
    assert.equal(res.data.error.code, 'UNAUTHORIZED_CHAT');
  });

  it('4. POST /api/v1/sos/:id/messages rejects random citizen chatting on another user alert', async () => {
    const alert = sosService.triggerSos({
      userId: 'usr_victim_real',
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    const bystanderUser = db.saveUser(createUser({
      id: 'usr_bystander',
      name: 'Curious Bystander',
      email: 'bystander@safesphere.test',
      phone: '+919999888877',
      role: 'citizen'
    }));

    const bystanderToken = tokenService.signAccessToken(bystanderUser, 'ses_bystander');

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${bystanderToken}` },
      body: { text: 'Can I see what is happening?' }
    });

    assert.equal(res.status, 403);
    assert.equal(res.data.success, false);
    assert.equal(res.data.error.code, 'FORBIDDEN_CHAT');
  });

  it('5. POST /api/v1/sos/:id/messages validates text length (1 to 500 characters)', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // Empty text
    const resEmpty = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { token: alert.resolveToken, text: '   ' }
    });
    assert.equal(resEmpty.status, 400);
    assert.equal(resEmpty.data.error.code, 'INVALID_CHAT_TEXT');

    // Oversized text (>500 chars)
    const resLong = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { token: alert.resolveToken, text: 'x'.repeat(501) }
    });
    assert.equal(resLong.status, 400);
    assert.equal(resLong.data.error.code, 'INVALID_CHAT_TEXT');
  });

  it('6. POST /api/v1/sos/:id/messages enforces 1 msg / 2s rate-limit', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // 1st message succeeds
    const res1 = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { token: alert.resolveToken, text: 'First message' }
    });
    assert.equal(res1.status, 201);

    // 2nd rapid message fails with 429
    const res2 = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { token: alert.resolveToken, text: 'Second rapid message' }
    });
    assert.equal(res2.status, 429);
    assert.equal(res2.data.error.code, 'RATE_LIMIT_EXCEEDED');
  });

  it('7. GET /api/v1/sos/:id/messages returns messages in chronological order for authorized caller', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // Insert 2 messages directly via DB
    db.saveSosMessage({
      alertId: alert.id,
      senderRole: 'victim',
      senderId: 'anonymous',
      text: 'Message 1 from victim',
      createdAt: '2026-11-20T10:00:00.000Z'
    });
    db.saveSosMessage({
      alertId: alert.id,
      senderRole: 'responder',
      senderId: 'usr_disp_1',
      text: 'Message 2 from dispatcher',
      createdAt: '2026-11-20T10:00:05.000Z'
    });

    // Retrieve via resolveToken
    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages?token=${alert.resolveToken}`);
    assert.equal(res.status, 200);
    assert.equal(res.data.success, true);
    assert.equal(res.data.count, 2);
    assert.equal(res.data.data[0].text, 'Message 1 from victim');
    assert.equal(res.data.data[1].text, 'Message 2 from dispatcher');
  });

  it('8. Enforces FIFO cap of 50 messages per alert', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // Seed 55 messages
    for (let i = 1; i <= 55; i++) {
      db.saveSosMessage({
        alertId: alert.id,
        senderRole: 'victim',
        senderId: 'anonymous',
        text: `Message ${i}`,
        createdAt: new Date(Date.now() + i * 1000).toISOString()
      });
    }

    const messages = db.getSosMessages(alert.id);
    assert.equal(messages.length, 50, 'Must cap at 50 messages');
    // First message should be Message 6 (1 to 5 purged)
    assert.equal(messages[0].text, 'Message 6');
    assert.equal(messages[49].text, 'Message 55');
  });

  it('9. WebSocket: handles CHAT_MESSAGE frame, verifies auth, and broadcasts to listeners', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    // Connect receiver socket
    const receiverWs = new WebSocket(wsUrl);
    await new Promise((resolve) => receiverWs.on('open', resolve));

    // Connect sender socket
    const senderWs = new WebSocket(wsUrl);
    await new Promise((resolve) => senderWs.on('open', resolve));

    const receivedMessages = [];
    receiverWs.on('message', (raw) => {
      try {
        const parsed = JSON.parse(raw.toString());
        if (parsed.type === 'CHAT_MESSAGE') {
          receivedMessages.push(parsed);
        }
      } catch (_) {}
    });

    // Send chat frame from sender
    senderWs.send(JSON.stringify({
      type: 'CHAT_MESSAGE',
      alertId: alert.id,
      token: alert.resolveToken,
      text: 'WebSocket real-time chat update from victim'
    }));

    // Await broadcast reception
    await new Promise((resolve) => {
      const check = setInterval(() => {
        if (receivedMessages.length > 0) {
          clearInterval(check);
          resolve();
        }
      }, 50);
    });

    receiverWs.close();
    senderWs.close();

    assert.equal(receivedMessages.length, 1);
    const chatPacket = receivedMessages[0];
    assert.equal(chatPacket.alertId, alert.id);
    assert.equal(chatPacket.message.senderRole, 'victim');
    assert.equal(chatPacket.message.text, 'WebSocket real-time chat update from victim');

    // Also verify persistence in DB
    const stored = db.getSosMessages(alert.id);
    assert.equal(stored.length, 1);
    assert.equal(stored[0].text, 'WebSocket real-time chat update from victim');
  });

  it('10. GET /api/v1/sos/:id/messages supports Authorization: Bearer <resolveToken> header', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    db.saveSosMessage({
      alertId: alert.id,
      senderRole: 'victim',
      senderId: 'anonymous',
      text: 'Bearer resolveToken test message',
      createdAt: new Date().toISOString()
    });

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      headers: { Authorization: `Bearer ${alert.resolveToken}` }
    });

    assert.equal(res.status, 200);
    assert.equal(res.data.success, true);
    assert.equal(res.data.count, 1);
    assert.equal(res.data.data[0].text, 'Bearer resolveToken test message');
  });

  it('11. Querying messages with limit returns the most recent messages in chronological order', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    for (let i = 1; i <= 5; i++) {
      db.saveSosMessage({
        alertId: alert.id,
        senderRole: 'victim',
        senderId: 'anonymous',
        text: `Chronological msg ${i}`,
        createdAt: new Date(Date.now() + i * 1000).toISOString()
      });
    }

    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages?limit=2`, {
      headers: { Authorization: `Bearer ${alert.resolveToken}` }
    });

    assert.equal(res.status, 200);
    assert.equal(res.data.count, 2);
    // Must return the last 2 messages (msg 4, msg 5) in chronological order
    assert.equal(res.data.data[0].text, 'Chronological msg 4');
    assert.equal(res.data.data[1].text, 'Chronological msg 5');
  });

  it('12. Unified rate-limiting: sending via WS and then rapid REST is blocked with 429', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    const ws = new WebSocket(wsUrl);
    await new Promise((resolve) => ws.on('open', resolve));

    // Send via WS
    ws.send(JSON.stringify({
      type: 'CHAT_MESSAGE',
      alertId: alert.id,
      token: alert.resolveToken,
      text: 'Message via WebSocket'
    }));

    await new Promise((resolve) => setTimeout(resolve, 50));
    ws.close();

    // Immediate attempt via REST should be rejected with 429
    const res = await apiRequest(`/api/v1/sos/${alert.id}/messages`, {
      method: 'POST',
      body: { token: alert.resolveToken, text: 'Immediate message via REST' }
    });

    assert.equal(res.status, 429);
    assert.equal(res.data.error.code, 'RATE_LIMIT_EXCEEDED');
  });

  it('13. WebSocket SUBSCRIBE_ALERT confirms room subscription', async () => {
    const alert = sosService.triggerSos({
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    const ws = new WebSocket(wsUrl);
    await new Promise((resolve) => ws.on('open', resolve));

    const events = [];
    ws.on('message', (raw) => {
      try {
        events.push(JSON.parse(raw.toString()));
      } catch (_) {}
    });

    ws.send(JSON.stringify({
      type: 'SUBSCRIBE_ALERT',
      alertId: alert.id
    }));

    await new Promise((resolve) => {
      const interval = setInterval(() => {
        if (events.some((e) => e.type === 'SUBSCRIBED_ALERT')) {
          clearInterval(interval);
          resolve();
        }
      }, 30);
    });

    ws.close();

    const subEvent = events.find((e) => e.type === 'SUBSCRIBED_ALERT');
    assert.ok(subEvent);
    assert.equal(subEvent.alertId, alert.id);
    assert.equal(subEvent.status, 'subscribed');
  });

  it('14. Account deletion cascades to purge all user sos_messages', async () => {
    const user = db.saveUser(createUser({
      id: 'usr_chat_purge_test',
      name: 'Purge User',
      email: 'purge@safesphere.test',
      phone: '+919111122222',
      role: 'citizen'
    }));

    const alert = sosService.triggerSos({
      userId: user.id,
      latitude: 28.6139,
      longitude: 77.2090,
      alertType: 'CRITICAL_SOS'
    });

    db.saveSosMessage({
      alertId: alert.id,
      senderRole: 'victim',
      senderId: user.id,
      text: 'Message to be purged with account'
    });

    assert.equal(db.getSosMessages(alert.id).length, 1);

    // Delete user
    db.deleteUser(user.id);

    // Alert and associated messages must be purged
    assert.equal(db.findAlertById(alert.id), null);
    assert.equal(db.getSosMessages(alert.id).length, 0);
  });
});
