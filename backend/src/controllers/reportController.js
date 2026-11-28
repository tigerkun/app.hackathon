/**
 * Report Controller
 * Handles incident reporting, listing, filtering, and retrieval.
 */

const crypto = require('crypto');
const config = require('../config');
const { db } = require('../data/store');
const { createReport, toSafeReport, VALID_REPORT_STATUSES } = require('../models/reportModel');
const { findNearby } = require('../services/geoService');

// M2.4: unverified reports expire 24h after creation — stale incidents
// auto-archive off the live feed instead of lingering for a day.
const REPORT_FRESHNESS_WINDOW_MS = 24 * 60 * 60 * 1000;
const UNVERIFIED_STATUSES = new Set(['pending', 'under_investigation']);
const CONSENSUS_VERIFY_RATIO = 0.7;
const CONSENSUS_REJECT_RATIO = 0.3;
const MIN_CONSENSUS_QUORUM = 5;
const MAX_CONSENSUS_QUORUM = 25;

function isPrivilegedUser(user) {
  return Boolean(
    user && (user.role === 'admin' || user.role === 'first_responder' || user.role === 'responder')
  );
}

function deriveThreadTag(reportId, userId) {
  if (!userId) return 'Anonymous';
  const secret = config.jwtSecret || 'safesphere_thread_tag_salt';
  const hex = crypto
    .createHmac('sha256', String(secret))
    .update(`${reportId}:${userId}`)
    .digest('hex')
    .slice(0, 4)
    .toUpperCase();
  return `Citizen #${hex}`;
}

function computeAreaQuorum(report) {
  if (!report || report.latitude === null || report.longitude === null) {
    return MIN_CONSENSUS_QUORUM;
  }
  const nearbyUsers = db.countNearbyActiveUsers(report.latitude, report.longitude, 15);
  return Math.max(
    MIN_CONSENSUS_QUORUM,
    Math.min(MAX_CONSENSUS_QUORUM, Math.ceil(nearbyUsers * 0.25))
  );
}

function getLockedReportQuorum(report) {
  const stored = Number(report?.quorumRequired);
  if (Number.isFinite(stored) && stored >= MIN_CONSENSUS_QUORUM) {
    return Math.min(MAX_CONSENSUS_QUORUM, Math.max(MIN_CONSENSUS_QUORUM, Math.round(stored)));
  }
  return computeAreaQuorum(report);
}

function recordPassiveUserLocation(user, lat, lng) {
  if (!user || !user.id || user.banned || !user.isActive) return;
  const nLat = Number(lat);
  const nLng = Number(lng);
  if (!Number.isFinite(nLat) || !Number.isFinite(nLng)) return;
  if (nLat < -90 || nLat > 90 || nLng < -180 || nLng > 180) return;
  db.updateUser(user.id, {
    lastKnownLat: nLat,
    lastKnownLng: nLng,
    lastSeenAt: new Date().toISOString()
  });
}

function decorateReportForViewer(report, viewerUser) {
  const isPrivileged = isPrivilegedUser(viewerUser);
  const myId = viewerUser ? viewerUser.id : null;
  const isOwner = Boolean(myId && report.reportedBy === myId);

  const safe = toSafeReport(report);
  const tally = db.getReportVoteTally(report.id);
  const upvotes = tally.upvotes;
  const downvotes = tally.downvotes;
  const totalVotes = upvotes + downvotes;
  const quorum = getLockedReportQuorum(report);
  const reporter = report.reportedBy ? db.findUserById(report.reportedBy) : null;

  safe.upvotes = upvotes;
  safe.downvotes = downvotes;
  safe.quorumRequired = quorum;
  safe.consensusRatio = totalVotes > 0 ? Math.round((upvotes / totalVotes) * 100) / 100 : 0;
  safe.verificationSource = report.verificationSource || (report.status === 'verified' ? 'moderator' : 'pending');
  safe.authorTag = deriveThreadTag(report.id, report.reportedBy);
  safe.authorKarma = reporter ? Number(reporter.reputationScore || 0) : 0;
  safe.commentCount = db.countReportComments(report.id);
  safe.expired = isReportExpired(report);
  safe.isMine = isOwner;
  // Anonymity invariant: never leak raw reportedBy user ID to unrelated citizens.
  safe.reportedBy = (isOwner || isPrivileged) ? (report.reportedBy ?? null) : null;

  const myVote = myId ? db.getUserReportVote(report.id, myId) : null;
  safe.myVote = myVote ? myVote.vote : null;
  return safe;
}

function reconcileVerdictKarma(report, targetStatus, { isSelfVerdict = false } = {}) {
  if (!report || !report.reportedBy) return null;
  const reporter = db.findUserById(report.reportedBy);
  if (!reporter) return null;

  const hasExplicit = Number.isFinite(Number(report.karmaDelta))
    && (Number(report.karmaDelta) !== 0 || Number(report.strikeApplied || 0) !== 0);
  let prevDelta = 0;
  let prevStrike = 0;
  if (hasExplicit) {
    prevDelta = Math.trunc(Number(report.karmaDelta));
    prevStrike = Math.max(0, Math.trunc(Number(report.strikeApplied || 0)));
  } else if (report.karmaAwarded) {
    if (report.status === 'rejected') {
      prevDelta = -20;
      prevStrike = 1;
    } else {
      prevDelta = 10;
      prevStrike = 0;
    }
  }

  let targetDelta = 0;
  let targetStrike = 0;
  if (targetStatus === 'verified') {
    targetDelta = 10;
    targetStrike = 0;
  } else if (targetStatus === 'rejected') {
    targetDelta = -20;
    targetStrike = 1;
  } else if (targetStatus === 'resolved') {
    if (prevDelta === 10 && prevStrike === 0) {
      targetDelta = 10;
      targetStrike = 0;
    }
  } else {
    // 'pending' or 'under_investigation': reverse prior verdict effects cleanly
    targetDelta = 0;
    targetStrike = 0;
  }

  if (isSelfVerdict && (targetDelta > prevDelta || targetStrike < prevStrike)) {
    targetDelta = prevDelta;
    targetStrike = prevStrike;
  }

  const repDiff = targetDelta - prevDelta;
  const strikeDiff = targetStrike - prevStrike;

  if (repDiff !== 0 || strikeDiff !== 0) {
    const newRep = Number(reporter.reputationScore || 0) + repDiff;
    const newStrikes = Math.max(0, Number(reporter.strikes || 0) + strikeDiff);
    const newBanned = newStrikes >= 3;
    db.updateUser(reporter.id, {
      reputationScore: newRep,
      strikes: newStrikes,
      banned: newBanned
    });
  }

  return {
    karmaDelta: targetDelta,
    strikeApplied: targetStrike,
    karmaAwarded: targetDelta !== 0 || targetStrike !== 0
  };
}

function ensureReportInteractive(res, report, actionLabel) {
  if (report.status === 'rejected') {
    res.status(409).json({
      success: false,
      error: {
        code: 'REPORT_REJECTED',
        message: `${actionLabel} is closed because this report has been rejected.`,
        details: []
      }
    });
    return true;
  }
  if (isReportExpired(report)) {
    res.status(409).json({
      success: false,
      error: {
        code: 'REPORT_EXPIRED',
        message: `${actionLabel} is closed because this unverified report has expired.`,
        details: []
      }
    });
    return true;
  }
  return false;
}

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
    const isPrivileged = isPrivilegedUser(req.user);
    const myId = req.user ? req.user.id : null;

    const filter = {};
    if (type) filter.type = String(type);
    if (status) filter.status = String(status).trim().toLowerCase();

    const reportedByValues = Array.isArray(reportedBy)
      ? reportedBy.map((v) => String(v ?? '').trim()).filter(Boolean)
      : (reportedBy !== undefined ? [String(reportedBy).trim()].filter(Boolean) : []);
    if (reportedByValues.length > 0) {
      const requestedReporter = reportedByValues[0];
      const hasUnauthorized = reportedByValues.some((val) => val !== myId);
      if (!isPrivileged && (!myId || hasUnauthorized || reportedByValues.length > 1)) {
        return res.status(403).json({
          success: false,
          error: {
            code: 'FORBIDDEN',
            message: 'You are not authorized to filter reports by another user.',
            details: []
          }
        });
      }
      filter.reportedBy = requestedReporter;
    }

    const mapVisible = req.query.mapVisible === 'true' || req.query.mapVisible === '1';
    if (mapVisible) filter.mapVisible = true;
    filter.includeRejected = isPrivileged && (filter.status === 'rejected' || req.query.includeRejected === 'true');

    const parsedLimit = limit !== undefined
      ? Math.min(Math.max(1, parseInt(limit, 10) || 100), 100)
      : 100;

    const latParam = req.query.latitude ?? req.query.lat;
    const lngParam = req.query.longitude ?? req.query.lng ?? req.query.lon;
    const radiusParam = req.query.radiusKm ?? req.query.radius;

    const decorate = (reports) => reports.map((r) => decorateReportForViewer(r, req.user));

    if (req.user && latParam !== undefined && lngParam !== undefined && latParam !== '' && lngParam !== '') {
      recordPassiveUserLocation(req.user, latParam, lngParam);
    }

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
          reportedBy: filter.reportedBy,
          includeRejected: filter.includeRejected,
          mapVisible: filter.mapVisible
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

    if (latitude !== undefined && latitude !== null && longitude !== undefined && longitude !== null) {
      recordPassiveUserLocation(req.user, latitude, longitude);
    }

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
    report.quorumRequired = computeAreaQuorum(report);

    // M2.4: unverified reports expire 24h after creation — stale unverified
    // reports auto-archive so old incidents don't linger on the live feed.
    const FRESHNESS_WINDOW_MS = 24 * 60 * 60 * 1000;
    report.expiresAt = new Date(
      new Date(report.createdAt).getTime() + FRESHNESS_WINDOW_MS
    ).toISOString();

    const saved = db.saveReport(report);
    const safeReport = decorateReportForViewer(saved, req.user);

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

    if (ensureReportInteractive(res, report, 'Voting')) return;

    // Users must not vote on their own reports — self-confirming inflates
    // credibility and defeats community verification.
    if (report.reportedBy && report.reportedBy === req.user.id) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'CANNOT_VOTE_OWN_REPORT',
          message: 'You cannot vote on a report you submitted.',
          details: []
        }
      });
    }

    const voteRecord = {
      id: `vte_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
      reportId: id,
      userId: req.user.id,
      vote,
      createdAt: new Date().toISOString()
    };
    db.saveReportVote(voteRecord);

    const tally = db.getReportVoteTally(id);
    const totalVotes = tally.upvotes + tally.downvotes;
    const confirmRatio = totalVotes > 0 ? tally.upvotes / totalVotes : 0;
    const quorum = getLockedReportQuorum(report);

    const updates = {
      upvotes: tally.upvotes,
      downvotes: tally.downvotes
    };

    // Dynamic 7:3 consensus evaluation for unverified reports once area quorum is met
    if (UNVERIFIED_STATUSES.has(report.status) && totalVotes >= quorum) {
      if (confirmRatio >= CONSENSUS_VERIFY_RATIO) {
        updates.status = 'verified';
        updates.verificationSource = 'community_consensus';
        updates.expiresAt = null;
        const karmaUpdates = reconcileVerdictKarma(report, 'verified');
        if (karmaUpdates) Object.assign(updates, karmaUpdates);
      } else if (confirmRatio < CONSENSUS_REJECT_RATIO) {
        updates.status = 'rejected';
        updates.verificationSource = 'community_rejected';
        const karmaUpdates = reconcileVerdictKarma(report, 'rejected');
        if (karmaUpdates) Object.assign(updates, karmaUpdates);
      }
    }

    const updated = db.updateReport(id, updates);
    const reporter = updated.reportedBy ? db.findUserById(updated.reportedBy) : null;

    res.status(200).json({
      success: true,
      message: `Vote recorded: ${vote}`,
      data: {
        reportId: id,
        myVote: vote,
        upvotes: tally.upvotes,
        downvotes: tally.downvotes,
        status: updated.status,
        verificationSource: updated.verificationSource,
        quorumRequired: quorum,
        consensusRatio: totalVotes > 0 ? Math.round((tally.upvotes / totalVotes) * 100) / 100 : 0,
        authorKarma: reporter ? Number(reporter.reputationScore || 0) : 0
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

    const viewerPrivileged = isPrivilegedUser(req.user);
    if (report.status === 'rejected' && !viewerPrivileged) {
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

    const safeReport = decorateReportForViewer(report, req.user);
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
    const isPrivileged = isPrivilegedUser(req.user);

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
    const updates = {
      status,
      verificationSource: (status === 'verified' || status === 'rejected' || status === 'resolved')
        ? 'moderator'
        : 'pending'
    };
    if (status === 'verified' || status === 'resolved') {
      updates.expiresAt = null;
    } else if ((status === 'pending' || status === 'under_investigation') && !existing.expiresAt) {
      updates.expiresAt = new Date(Date.now() + REPORT_FRESHNESS_WINDOW_MS).toISOString();
    }

    // M2.5/M2.6: moderator verdicts drive reporter reputation, strikes, and
    // bans. 'verified' = +10; 'rejected' = -20 + 1 strike (3 strikes = banned).
    // Reconcile deltas cleanly so consensus->moderator overrides and reversals
    // never double-award or leave stale penalties/bans intact.
    const isSelfVerdict = Boolean(existing.reportedBy) && existing.reportedBy === req.user.id;
    if (existing.reportedBy) {
      const karmaUpdates = reconcileVerdictKarma(existing, status, { isSelfVerdict });
      if (karmaUpdates) Object.assign(updates, karmaUpdates);
    }

    const updated = db.updateReport(id, updates);
    const safeReport = decorateReportForViewer(updated, req.user);

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

function decorateCommentForViewer(comment, report, viewerUser) {
  const myId = viewerUser ? viewerUser.id : null;
  const author = comment.userId ? db.findUserById(comment.userId) : null;
  const tally = db.getCommentVoteTally(comment.id);
  const myVote = myId ? db.getUserCommentVote(comment.id, myId) : null;
  return {
    id: comment.id,
    reportId: comment.reportId,
    parentId: comment.parentId ?? null,
    body: comment.body,
    authorTag: deriveThreadTag(report.id, comment.userId),
    authorKarma: author ? Number(author.reputationScore || 0) : 0,
    isOp: Boolean(report.reportedBy && comment.userId && report.reportedBy === comment.userId),
    isMine: Boolean(myId && comment.userId === myId),
    upvotes: tally.upvotes,
    downvotes: tally.downvotes,
    myVote: myVote ? myVote.vote : null,
    createdAt: comment.createdAt
  };
}

function listComments(req, res, next) {
  try {
    const { id } = req.params;
    const report = db.findReportById(id);
    if (!report) {
      return res.status(404).json({
        success: false,
        error: { code: 'REPORT_NOT_FOUND', message: `Report with ID ${id} not found`, details: [] }
      });
    }

    const viewerPrivileged = isPrivilegedUser(req.user);
    if (report.status === 'rejected' && !viewerPrivileged) {
      return res.status(404).json({
        success: false,
        error: { code: 'REPORT_NOT_FOUND', message: `Report with ID ${id} not found`, details: [] }
      });
    }

    if (isReportExpired(report)) {
      const viewerId = req.user ? req.user.id : null;
      if (!(viewerId && report.reportedBy === viewerId) && !viewerPrivileged) {
        return res.status(404).json({
          success: false,
          error: { code: 'REPORT_NOT_FOUND', message: `Report with ID ${id} not found`, details: [] }
        });
      }
    }

    const comments = db.getReportComments(id).map((c) => decorateCommentForViewer(c, report, req.user));
    res.status(200).json({
      success: true,
      count: comments.length,
      data: comments
    });
  } catch (err) {
    next(err);
  }
}

function createComment(req, res, next) {
  try {
    if (!req.user || !req.user.id) {
      return res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Sign in to comment on reports.', details: [] }
      });
    }
    if (req.user.banned) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'INSUFFICIENT_REPUTATION',
          message: 'This account is banned from community interactions after repeated false reports.',
          details: []
        }
      });
    }
    if (!req.user.phoneVerified) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'PHONE_NOT_VERIFIED',
          message: 'Verify your account with the OTP sent at sign-up before commenting.',
          details: []
        }
      });
    }

    const { id } = req.params;
    const report = db.findReportById(id);
    if (!report) {
      return res.status(404).json({
        success: false,
        error: { code: 'REPORT_NOT_FOUND', message: `Report with ID ${id} not found`, details: [] }
      });
    }
    if (ensureReportInteractive(res, report, 'Commenting')) return;

    const rawBody = req.body?.body ?? req.body?.text;
    const parentId = req.body?.parentId ? String(req.body.parentId).trim() : null;
    if (!rawBody || typeof rawBody !== 'string' || !rawBody.trim() || rawBody.trim().length > 1000) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Comment must be between 1 and 1000 characters.',
          details: [{ field: 'body', issue: 'Comment body must be 1..1000 characters.' }]
        }
      });
    }

    if (parentId) {
      const parent = db.findReportCommentById(parentId);
      if (!parent || parent.reportId !== id) {
        return res.status(400).json({
          success: false,
          error: {
            code: 'VALIDATION_ERROR',
            message: 'Parent comment not found on this report.',
            details: [{ field: 'parentId', issue: 'Invalid parentId for this report.' }]
          }
        });
      }
    }

    const commentId = `cmt_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
    const saved = db.saveReportComment({
      id: commentId,
      reportId: id,
      userId: req.user.id,
      parentId,
      body: rawBody.trim()
    });

    const decorated = decorateCommentForViewer(saved, report, req.user);
    res.status(201).json({
      success: true,
      message: 'Comment posted anonymously',
      data: decorated
    });
  } catch (err) {
    next(err);
  }
}

function voteComment(req, res, next) {
  try {
    if (!req.user || !req.user.id) {
      return res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Sign in to vote on comments.', details: [] }
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
    if (!req.user.phoneVerified) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'PHONE_NOT_VERIFIED',
          message: 'Verify your account before voting on comments.',
          details: []
        }
      });
    }

    const { id, commentId } = req.params;
    const { vote } = req.body || {};
    if (vote !== 'confirm' && vote !== 'decline') {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'vote must be "confirm" or "decline".', details: [] }
      });
    }

    const report = db.findReportById(id);
    if (!report) {
      return res.status(404).json({
        success: false,
        error: { code: 'REPORT_NOT_FOUND', message: `Report with ID ${id} not found`, details: [] }
      });
    }
    if (ensureReportInteractive(res, report, 'Comment voting')) return;

    const comment = db.findReportCommentById(commentId);
    if (!comment || comment.reportId !== id) {
      return res.status(404).json({
        success: false,
        error: { code: 'COMMENT_NOT_FOUND', message: `Comment ${commentId} not found`, details: [] }
      });
    }

    if (comment.userId && comment.userId === req.user.id) {
      return res.status(403).json({
        success: false,
        error: { code: 'CANNOT_VOTE_OWN_COMMENT', message: 'You cannot vote on your own comment.', details: [] }
      });
    }

    db.saveCommentVote({
      id: `cmv_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
      commentId,
      userId: req.user.id,
      vote,
      createdAt: new Date().toISOString()
    });

    const tally = db.getCommentVoteTally(commentId);
    res.status(200).json({
      success: true,
      message: `Comment vote recorded: ${vote}`,
      data: {
        commentId,
        myVote: vote,
        upvotes: tally.upvotes,
        downvotes: tally.downvotes
      }
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
  vote,
  listComments,
  createComment,
  voteComment
};
