/**
 * SOS Message Entity Model
 * SafeSphere real-time two-way responder chat schema.
 */

const crypto = require('crypto');

function generateSosMessageId() {
  return `msg_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_SENDER_ROLES = ['victim', 'responder', 'admin'];

function createSosMessage({
  id = generateSosMessageId(),
  alertId,
  senderRole,
  senderId = null,
  text,
  createdAt = new Date().toISOString()
}) {
  return {
    id,
    alertId,
    senderRole: VALID_SENDER_ROLES.includes(senderRole) ? senderRole : 'victim',
    senderId: senderId ? String(senderId) : null,
    text: (text || '').trim(),
    createdAt
  };
}

function toSafeSosMessage(msg) {
  if (!msg) return null;
  return {
    id: msg.id,
    alertId: msg.alertId,
    senderRole: msg.senderRole,
    senderId: msg.senderId ?? null,
    text: msg.text,
    createdAt: msg.createdAt
  };
}

module.exports = {
  createSosMessage,
  toSafeSosMessage,
  generateSosMessageId,
  VALID_SENDER_ROLES
};
