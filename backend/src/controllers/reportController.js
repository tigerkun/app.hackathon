/**
 * Report Controller
 * Handles incident reporting, listing, filtering, and retrieval.
 */

const { db } = require('../data/store');
const { createReport, toSafeReport, VALID_REPORT_STATUSES } = require('../models/reportModel');
const { findNearby } = require('../services/geoService');

// M2.4: unverified reports expire 24h after creation — stale incidents
// auto-archive off the live feed instead of lingering for a day.
const REPORT_FRESHNESS_WINDOW_MS = 24 * 60 * 60 * 1000;
const UNVERIFIED_STATUSES = new Set(['pending', 'under_investigation']);

// Expiry instant: persisted expiresAt wins; fall back to createdAt + window
// for rows written before the column existed.
function reportExpiryMs(r) {
  const exp = r.expiresAt ? new Date(r.expiresAt).getTime() : NaN;
  if (!isNaN(exp)) return exp;
  const created = r.createdAt ? new Date(r.createdAt).getTime() : NaN;
  return isNaN(created) ? NaN : created + REPORT_FRESHNESS_WINDOW_MS;
}

function isReportExpired(r) {
  if (!UNVERIFIED_STATUSES.has(r.status)) return false;
  const exp = reportExpiryMs(r);
  return !isNaN(exp) && Date.now() > exp;
}

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

    // M2.4: is the caller privileged (moderator/admin/responder) or the
    // report owner? Privileged/owner views include expired unverified
    // reports; the default public feed hides them.
    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );
    const myId = req.user ? req.user.id : null;

    const latParam = req.query.latitude ?? req.query.lat;
    const lngParam = req.query.longitude ?? req.query.lng ?? req.query.lon;
    const radiusParam = req.query.radiusKm ?? req.query.radius;

    const decorate = (reports) => reports.map((r) => {
      const safe = toSafeReport(r);
      const tally = db.getReportVoteTally(r.id);
      safe.upvotes = tally.upvotes;
      safe.downvotes = tally.downvotes;
      safe.expired = isReportExpired(r);
      safe.isMine = Boolean(myId && r.reportedBy === myId);
      const myVote = myId ? db.getUserReportVote(r.id, myId) : null;
      safe.myVote = myVote ? myVote.vote : null;
      return safe;
    });

    // M2.4 freshness: expired unverified reports drop out of the default feed
    const isFreshEnough = (r) => !isReportExpired(r);

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
        const nearbyReports = findNearby(
          allMatching.filter((r) => isPrivileged || r.reportedBy === myId || isFreshEnough(r)),
          targetLat, targetLng, radiusKm
        );
        const sliced = nearbyReports.slice(0, parsedLimit);
        return res.status(200).json({
          success: true,
          count: sliced.length,
          data: decorate(sliced)
        });
      }
    }

    filter.limit = parsedLimit;
    const reports = db.getAllReports(filter)
      .filter((r) => isPrivileged || r.reportedBy === myId || isFreshEnough(r));

    res.status(200).json({
      success: true,
      count: reports.length,
      data: decorate(reports)
    });
  } catch (err) {
    next(err);
  }
}

function create(req, res, next) {
  try {
    // M2.1: community reports require an OTP-verified authenticated account —
    // guests can view but not submit (anti-fake-report gating).
    if (!req.user || !req.user.id) {
      return res.status(401).json({
        success: false,
        error: {
          code: 'SIGN_IN_REQUIRED',
          message: 'Sign in with a verified account to submit community reports.',
          details: []
        }
      });
    }

    // M2.1/M2.3: reporting requires an OTP-verified phone — unverified or
    // fake-phone accounts must not be able to submit or brigade votes.
    if (!req.user.phoneVerified) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'PHONE_NOT_VERIFIED',
          message: 'Verify your phone number with the OTP sent at sign-up before reporting.',
          details: []
        }
      });
    }

    // M2.5: banned users cannot create reports (SOS/tracking/chat/dialer are
    // NEVER gated — safety invariants are absolute).
    if (req.user.banned) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'INSUFFICIENT_REPUTATION',
          message: 'This account is banned from community submissions after repeated false reports.',
          details: []
        }
      });
    }

    const { type, description, location, latitude, longitude, attachments, photoUrl } = req.body;
    const reportedBy = req.user.id;

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

    // M2.4: unverified reports expire 24h after creation — stale unverified
    // reports auto-archive so old incidents don't linger on the live feed.
    const FRESHNESS_WINDOW_MS = 24 * 60 * 60 * 1000;
    report.expiresAt = new Date(
      new Date(report.createdAt).getTime() + FRESHNESS_WINDOW_MS
    ).toISOString();

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

/**
 * M2.3: Community voting — one vote per verified user per report
 * ('confirm' | 'decline'). Banned users cannot vote.
 */
function vote(req, res, next) {
  try {
    if (!req.user || !req.user.id) {
      return res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHORIZED',
          message: 'Sign in to vote on community reports.',
          details: []
        }
      });
    }

    if (req.user.banned) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'INSUFFICIENT_REPUTATION',
          message: 'This account is banned from community voting after repeated false reports.',
          details: []
        }
      });
    }

    // M2.3: voting requires the same OTP-verified account as reporting.
    if (!req.user.phoneVerified) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'PHONE_NOT_VERIFIED',
          message: 'Verify your phone number with the OTP sent at sign-up before voting.',
          details: []
        }
      });
    }

    const { id } = req.params;
    const { vote } = req.body || {};

    if (vote !== 'confirm' && vote !== 'decline') {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'vote must be "confirm" or "decline".',
          details: []
        }
      });
    }

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

    const crypto = require('crypto');
    const voteRecord = {
      id: `vte_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
      reportId: id,
      userId: req.user.id,
      vote,
      createdAt: new Date().toISOString()
    };
    db.saveReportVote(voteRecord);

    const tally = db.getReportVoteTally(id);
    db.updateReport(id, {
      upvotes: tally.upvotes,
      downvotes: tally.downvotes
    });

    res.status(200).json({
      success: true,
      message: `Vote recorded: ${vote}`,
      data: {
        reportId: id,
        myVote: vote,
        upvotes: tally.upvotes,
        downvotes: tally.downvotes
      }
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

    // M2.4: expired unverified reports are invisible to the public — the
    // by-ID route must apply the same rule the feed does, or it becomes a
    // bypass for stale/archived incidents. Owner and privileged roles still
    // see their own reports for moderation/history.
    if (isReportExpired(report)) {
      const viewerId = req.user ? req.user.id : null;
      const viewerPrivileged = Boolean(
        req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
      );
      const isOwner = Boolean(viewerId && report.reportedBy === viewerId);
      if (!isOwner && !viewerPrivileged) {
        return res.status(404).json({
          success: false,
          error: {
            code: 'REPORT_NOT_FOUND',
            message: `Report with ID ${id} not found`,
            details: []
          }
        });
      }
    }

    const safeReport = toSafeReport(report);
    const tally = db.getReportVoteTally(report.id);
    safeReport.upvotes = tally.upvotes;
    safeReport.downvotes = tally.downvotes;
    safeReport.expired = isReportExpired(report);
    const viewerId = req.user ? req.user.id : null;
    safeReport.isMine = Boolean(viewerId && report.reportedBy === viewerId);
    const myVote = viewerId ? db.getUserReportVote(report.id, viewerId) : null;
    safeReport.myVote = myVote ? myVote.vote : null;
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

    // M2.5: verified reports persist — clear the freshness expiry on verdicts
    const updates = { status };
    if (status === 'verified' || status === 'resolved') updates.expiresAt = null;
    const updated = db.updateReport(id, updates);
    const safeReport = toSafeReport(updated);

    // M2.5/M2.6: moderator verdicts drive reporter reputation, strikes, and
    // bans. 'verified' = accurate report (+10, expiry cleared — verified
    // reports persist); 'rejected' = false report (-20, +1 strike, 3 strikes
    // = banned from community submissions). SOS/tracking/chat/dialer are
    // NEVER gated by any of this (safety invariants are absolute).
    //
    // Effects apply ONLY on the first terminal verdict: re-issuing the same
    // status or flip-flopping verified↔rejected must not farm reputation or
    // stack strikes. Moderators also get no reputation for verdicts on their
    // OWN reports (self-verdict farming).
    const isFirstVerdict = !['verified', 'rejected', 'resolved'].includes(existing.status);
    const isSelfVerdict = Boolean(updated.reportedBy) && updated.reportedBy === req.user.id;
    if (updated.reportedBy && isFirstVerdict && !isSelfVerdict) {
      const reporter = db.findUserById(updated.reportedBy);
      if (reporter) {
        let reputation = Number(reporter.reputationScore || 0);
        let strikes = Number(reporter.strikes || 0);
        let banned = Boolean(reporter.banned);

        if (status === 'verified') {
          reputation += 10;
        } else if (status === 'rejected') {
          reputation -= 20;
          strikes += 1;
          if (strikes >= 3) banned = true;
        }

        if (reputation !== Number(reporter.reputationScore || 0) ||
            strikes !== Number(reporter.strikes || 0) ||
            banned !== Boolean(reporter.banned)) {
          db.updateUser(reporter.id, {
            reputationScore: reputation,
            strikes,
            banned
          });
        }
      }
    }

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
  updateStatus,
  vote
};
