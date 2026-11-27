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
  quorumRequired = 5,
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
    quorumRequired: Math.max(5, Number(quorumRequired) || 5),
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
    quorumRequired: Math.max(5, Number(report.quorumRequired || 5)),
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
