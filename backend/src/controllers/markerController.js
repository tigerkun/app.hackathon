/**
 * Marker Controller
 * Handles verified safety markers, facilities listing, and proximity searches using Haversine calculation.
 */

const { db } = require('../data/store');
const { createMarker } = require('../models/markerModel');
const { findNearby } = require('../services/geoService');

function list(req, res, next) {
  try {
    const { category, isVerified, lat, lon, latitude, longitude, radius } = req.query;

    const targetLat = lat || latitude;
    const targetLon = lon || longitude;

    // If coordinates are provided in query, perform proximity search
    if (targetLat !== undefined && targetLon !== undefined) {
      const allMarkers = db.getAllMarkers();
      const nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, radius || 10);

      return res.status(200).json({
        success: true,
        count: nearbyMarkers.length,
        data: nearbyMarkers
      });
    }

    const filter = {};
    if (category) filter.category = String(category);
    if (isVerified !== undefined) filter.isVerified = isVerified === 'true';

    const markers = db.getAllMarkers(filter);

    res.status(200).json({
      success: true,
      count: markers.length,
      data: markers
    });
  } catch (err) {
    next(err);
  }
}

function nearby(req, res, next) {
  try {
    const { lat, lon, latitude, longitude, radius } = req.query;
    const targetLat = lat || latitude;
    const targetLon = lon || longitude;

    if (targetLat === undefined || targetLon === undefined) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_COORDINATES',
          message: 'latitude and longitude are required query parameters',
          details: []
        }
      });
    }

    const allMarkers = db.getAllMarkers();
    const nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, radius || 10);

    res.status(200).json({
      success: true,
      count: nearbyMarkers.length,
      data: nearbyMarkers
    });
  } catch (err) {
    next(err);
  }
}

function create(req, res, next) {
  try {
    const { name, category, latitude, longitude, address, isVerified } = req.body;

    if (!name || latitude === undefined || longitude === undefined) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'name, latitude, and longitude are required',
          details: []
        }
      });
    }

    const marker = createMarker({
      name,
      category,
      latitude,
      longitude,
      address,
      isVerified: isVerified !== undefined ? isVerified : true
    });

    const saved = db.saveMarker(marker);

    res.status(201).json({
      success: true,
      message: 'Safety marker created successfully',
      data: saved
    });
  } catch (err) {
    next(err);
  }
}

function getById(req, res, next) {
  try {
    const { id } = req.params;
    const marker = db.findMarkerById(id);

    if (!marker) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'MARKER_NOT_FOUND',
          message: `Marker with ID ${id} not found`,
          details: []
        }
      });
    }

    res.status(200).json({
      success: true,
      data: marker
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  list,
  nearby,
  create,
  getById
};
