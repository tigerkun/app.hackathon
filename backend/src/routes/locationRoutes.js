/**
 * Location Tracking Routes
 * Express routes for /api/v1/location/*
 */

const express = require('express');
const locationController = require('../controllers/locationController');
const { optionalAuth, requireAuth } = require('../middleware/authMiddleware');

const router = express.Router();

// M5: privacy hub — the owner's own live sessions (token scrubbed).
router.get('/sessions/mine', requireAuth, locationController.listMine);
// Owner stops their own live trip from the privacy hub (account-authed).
router.post('/sessions/:sessionId/terminate', requireAuth, locationController.terminateMine);

router.post('/share-session', optionalAuth, locationController.shareSession);
router.get('/track/:sessionId', locationController.getTrack);
router.post('/ping', locationController.ping);
router.post('/terminate/:sessionId', locationController.terminate);
router.post('/terminate', locationController.terminate);

module.exports = router;
