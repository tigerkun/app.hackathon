/**
 * Connection Routes
 * M3: Express routes for /api/v1/connections/* — account-to-account trusted
 * circle. Every route requires auth; scoped reads re-verify grant per request
 * (revocation is immediate, no cached access).
 */

const express = require('express');
const connectionController = require('../controllers/connectionController');
const { requireAuth } = require('../middleware/authMiddleware');

const router = express.Router();

router.post('/', requireAuth, connectionController.createConnection);
router.get('/mine', requireAuth, connectionController.getMyConnections);
router.post('/:id/respond', requireAuth, connectionController.respondToConnection);
router.post('/:id/revoke', requireAuth, connectionController.revokeConnection);
router.patch('/:id/scopes', requireAuth, connectionController.updateScopes);
router.post('/:id/ping', requireAuth, connectionController.pingLocation);
router.get('/:id/live', requireAuth, connectionController.getLiveLocation);
router.get('/:id/alerts', requireAuth, connectionController.getOwnerAlerts);
router.get('/:id/status', requireAuth, connectionController.getOwnerStatus);
router.post('/:id/checkin', requireAuth, connectionController.checkIn);

module.exports = router;
