/**
 * Incident Report Entity Model
 * SafeSphere community safety incident and hazard schema.
 */

const crypto = require('crypto');

function generateReportId() {
  return `rep_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
}

const VALID_REPORT_TYPES = ['Theft', 'Harassment', 'Accident', 'Suspicious', 'Other'];
const VALID_REPORT_STATUSES = ['pending', 'under_investigation', 'verified', 'resolved'];

function createReport({
  id = generateReportId(),
  type = 'Other',
  description,
  location,
  latitude = null,
  longitude = null,
  status = 'pending',
  reportedBy = null,
  attachments = [],
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
    attachments: Array.isArray(attachments) ? attachments : [],
    createdAt,
    updatedAt
  };
}

module.exports = {
  createReport,
  generateReportId,
  VALID_REPORT_TYPES,
  VALID_REPORT_STATUSES
};
