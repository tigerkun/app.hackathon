/**
 * Incident Report Entity Model
 * SafeSphere community safety incident and hazard schema.
 */

const crypto = require('crypto');

function generateReportId() {
  return `rep_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_REPORT_TYPES = [
  'Theft',
  'Harassment',
  'Assault',
  'Suspicious',
  'Accident',
  'Dark Area',
  'Road Hazard',
  'Flooding',
  'Transit Issue',
  'Other'
];
const VALID_REPORT_STATUSES = ['pending', 'under_investigation', 'verified', 'resolved', 'rejected'];
const VALID_VERIFICATION_SOURCES = ['pending', 'moderator', 'community_consensus', 'community_rejected'];

const MIN_REPORT_QUORUM = 5;
const MAX_REPORT_QUORUM = 25;

function clampQuorum(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) return MIN_REPORT_QUORUM;
  return Math.min(MAX_REPORT_QUORUM, Math.max(MIN_REPORT_QUORUM, Math.round(num)));
}

function createReport({
  id = generateReportId(),
  type = 'Other',
  description,
  location,
  latitude = null,
  longitude = null,
  status = 'pending',
  reportedBy = null,
  verificationSource = 'pending',
  karmaAwarded = false,
  karmaDelta = 0,
  strikeApplied = 0,
  quorumRequired = MIN_REPORT_QUORUM,
  expiresAt = null,
  attachments = [],
  photoUrl = null,
  createdAt = new Date().toISOString(),
  updatedAt = new Date().toISOString()
}) {
  return {
    id,
    type: VALID_REPORT_TYPES.includes(type) ? type : 'Other',
    description: (description || '').trim(),
    location: (location || '').trim(),
    latitude: latitude !== null ? Number(latitude) : null,
    longitude: longitude !== null ? Number(longitude) : null,
    status: VALID_REPORT_STATUSES.includes(status) ? status : 'pending',
    reportedBy: reportedBy ? String(reportedBy) : null,
    verificationSource: VALID_VERIFICATION_SOURCES.includes(verificationSource) ? verificationSource : 'pending',
    karmaAwarded: Boolean(karmaAwarded),
    karmaDelta: Number.isFinite(Number(karmaDelta)) ? Math.trunc(Number(karmaDelta)) : 0,
    strikeApplied: Number.isFinite(Number(strikeApplied)) ? Math.max(0, Math.trunc(Number(strikeApplied))) : 0,
    quorumRequired: clampQuorum(quorumRequired),
    expiresAt,
    attachments: Array.isArray(attachments) ? attachments : [],
    photoUrl: photoUrl ? String(photoUrl).trim() : null,
    createdAt,
    updatedAt
  };
}

function toSafeReport(report) {
  if (!report) return null;
  const upvotes = Number(report.upvotes || 0);
  const downvotes = Number(report.downvotes || 0);
  const totalVotes = upvotes + downvotes;
  return {
    id: report.id,
    type: report.type,
    description: report.description,
    location: report.location,
    latitude: report.latitude ?? null,
    longitude: report.longitude ?? null,
    status: report.status,
    verificationSource: report.verificationSource || (report.status === 'verified' ? 'moderator' : 'pending'),
    quorumRequired: clampQuorum(report.quorumRequired),
    reportedBy: report.reportedBy ?? null,
    attachments: Array.isArray(report.attachments) ? report.attachments : [],
    photoUrl: report.photoUrl ?? null,
    expiresAt: report.expiresAt ?? null,
    upvotes,
    downvotes,
    consensusRatio: totalVotes > 0 ? Math.round((upvotes / totalVotes) * 100) / 100 : 0,
    createdAt: report.createdAt,
    updatedAt: report.updatedAt,
    ...(report.distanceKm !== undefined ? { distanceKm: report.distanceKm } : {})
  };
}

module.exports = {
  createReport,
  toSafeReport,
  generateReportId,
  VALID_REPORT_TYPES,
  VALID_REPORT_STATUSES,
  VALID_VERIFICATION_SOURCES
};
