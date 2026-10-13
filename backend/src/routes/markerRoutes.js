/**
 * Marker Routes
 * Express routes for /api/v1/markers/*
 */

const express = require('express');
const markerController = require('../controllers/markerController');

const router = express.Router();

router.get('/', markerController.list);
router.get('/nearby', markerController.nearby);
router.post('/', markerController.create);
router.get('/:id', markerController.getById);

module.exports = router;
