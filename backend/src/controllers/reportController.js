/**
 * Report Controller
 * Handles incident reporting, listing, filtering, and retrieval.
 */

const { db } = require('../data/store');
const { createReport, toSafeReport, VALID_REPORT_STATUSES } = require('../models/reportModel');
const { findNearby } = require('../services/geoService');

function list(req, res, next) {
  try {
    const { type, status, limit, reportedBy } = req.query;
    const filter = {};
    if (type) filter.type = String(type);
    if (status) filter.status = String(status);
    if (reportedBy) filter.reportedBy = String(reportedBy);
    const parsedLimit = limit !== undefined
      ? Math.min(Math.max(1, parseInt(limit, 10) || 100), 100)
      : 100;

    const latParam = req.query.latitude ?? req.query.lat;
    const lngParam = req.query.longitude ?? req.query.lng ?? req.query.lon;
    const radiusParam = req.query.radiusKm ?? req.query.radius;

    if (latParam !== undefined && lngParam !== undefined && latParam !== '' && lngParam !== '') {
      const targetLat = Number(latParam);
      const targetLng = Number(lngParam);
      if (!isNaN(targetLat) && !isNaN(targetLng)) {
        let radiusKm = 10;
        if (radiusParam !== undefined && radiusParam !== '') {
          const parsed = Number(radiusParam);
          if (!isNaN(parsed)) {
            radiusKm = Math.max(1, Math.min(parsed, 50));
          }
        }
        // Fetch matching reports without limit, filter by proximity, then apply limit
        const allMatching = db.getAllReports({
          type: filter.type,
          status: filter.status,
          reportedBy: filter.reportedBy
        });
        const nearbyReports = findNearby(allMatching, targetLat, targetLng, radiusKm);
        const sliced = nearbyReports.slice(0, parsedLimit);
        return res.status(200).json({
          success: true,
          count: sliced.length,
          data: sliced.map(r => toSafeReport(r))
        });
      }
    }

    filter.limit = parsedLimit;
    const reports = db.getAllReports(filter);

    res.status(200).json({
      success: true,
      count: reports.length,
      data: reports.map(r => toSafeReport(r))
    });
  } catch (err) {
    next(err);
  }
}

function create(req, res, next) {
  try {
    const { type, description, location, latitude, longitude, attachments, photoUrl } = req.body;
    const reportedBy = req.user ? req.user.id : null;

    const report = createReport({
      type,
      description,
      location,
      latitude,
      longitude,
      reportedBy,
      attachments,
      photoUrl: photoUrl || null
    });

    const saved = db.saveReport(report);
    const safeReport = toSafeReport(saved);

    res.status(201).json({
      success: true,
      message: 'Incident report submitted successfully',
      data: safeReport,
      report: safeReport
    });
  } catch (err) {
    next(err);
  }
}

function getById(req, res, next) {
  try {
    const { id } = req.params;
    const report = db.findReportById(id);

    if (!report) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'REPORT_NOT_FOUND',
          message: `Report with ID ${id} not found`,
          details: []
        }
      });
    }

    const safeReport = toSafeReport(report);
    res.status(200).json({
      success: true,
      data: safeReport,
      report: safeReport
    });
  } catch (err) {
    next(err);
  }
}

function updateStatus(req, res, next) {
  try {
    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    if (!isPrivileged) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Admin or responder privileges required to update report status',
          details: []
        }
      });
    }

    const { id } = req.params;
    const { status } = req.body;

    if (!status || !VALID_REPORT_STATUSES.includes(status)) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: `Invalid report status. Must be one of: ${VALID_REPORT_STATUSES.join(', ')}`,
          details: []
        }
      });
    }

    const existing = db.findReportById(id);
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'REPORT_NOT_FOUND',
          message: `Report with ID ${id} not found`,
          details: []
        }
      });
    }

    const updated = db.updateReport(id, { status });
    const safeReport = toSafeReport(updated);

    res.status(200).json({
      success: true,
      message: `Report status updated to ${status}`,
      data: safeReport,
      report: safeReport
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  list,
  create,
  getById,
  updateStatus
};
