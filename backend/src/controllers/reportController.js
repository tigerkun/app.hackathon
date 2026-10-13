/**
 * Report Controller
 * Handles incident reporting, listing, filtering, and retrieval.
 */

const { db } = require('../data/store');
const { createReport } = require('../models/reportModel');

function list(req, res, next) {
  try {
    const { type, status, limit } = req.query;
    const filter = {};
    if (type) filter.type = String(type);
    if (status) filter.status = String(status);
    if (limit) filter.limit = parseInt(limit, 10);

    const reports = db.getAllReports(filter);

    res.status(200).json({
      success: true,
      count: reports.length,
      data: reports
    });
  } catch (err) {
    next(err);
  }
}

function create(req, res, next) {
  try {
    const { type, description, location, latitude, longitude, attachments } = req.body;
    const reportedBy = req.user ? req.user.id : null;

    const report = createReport({
      type,
      description,
      location,
      latitude,
      longitude,
      reportedBy,
      attachments
    });

    const saved = db.saveReport(report);

    res.status(201).json({
      success: true,
      message: 'Incident report submitted successfully',
      data: saved,
      report: saved
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

    res.status(200).json({
      success: true,
      data: report,
      report
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  list,
  create,
  getById
};
