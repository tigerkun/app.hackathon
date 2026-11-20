/**
 * Marker Controller
 * Handles verified safety markers, facilities listing, and proximity searches using Haversine calculation.
 */

const { db } = require('../data/store');
const { createMarker } = require('../models/markerModel');
const { findNearby } = require('../services/geoService');

function list(req, res, next) {
  try {
    const { category, isVerified, lat, lon, latitude, longitude, radius, limit } = req.query;

    const targetLat = lat || latitude;
    const targetLon = lon || longitude;
    const parsedLimit = Math.min(Math.max(1, parseInt(limit, 10) || 100), 100);

    // If coordinates are provided in query, perform proximity search
    if (targetLat !== undefined && targetLon !== undefined) {
      const maxRadius = Math.min(Math.max(0.1, Number(radius) || 10), 100);
      const allMarkers = db.getAllMarkers();
      const nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, maxRadius).slice(0, parsedLimit);

      return res.status(200).json({
        success: true,
        count: nearbyMarkers.length,
        data: nearbyMarkers
      });
    }

    const filter = {};
    if (category) filter.category = String(category);
    if (isVerified !== undefined) filter.isVerified = isVerified === 'true';
    filter.limit = parsedLimit;

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
    const { lat, lon, latitude, longitude, radius, category, type, limit } = req.query;
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

    let allMarkers = db.getAllMarkers();
    const filterCat = category || type;
    if (filterCat) {
      allMarkers = allMarkers.filter(m =>
        m.category && m.category.toLowerCase().includes(String(filterCat).toLowerCase())
      );
    }
    const maxRadius = Math.min(Math.max(0.1, Number(radius) || 10), 100);
    const parsedLimit = Math.min(Math.max(1, parseInt(limit, 10) || 100), 100);
    const nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, maxRadius).slice(0, parsedLimit);

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
    const { name, category, latitude, longitude, address } = req.body;

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

    const latNum = Number(latitude);
    const lonNum = Number(longitude);
    if (isNaN(latNum) || isNaN(lonNum) || latNum < -90 || latNum > 90 || lonNum < -180 || lonNum > 180) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'latitude must be between -90 and 90, and longitude between -180 and 180',
          details: []
        }
      });
    }

    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    const marker = createMarker({
      name,
      category,
      latitude: latNum,
      longitude: lonNum,
      address,
      isVerified: isPrivileged
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

function pending(req, res, next) {
  try {
    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    if (!isPrivileged) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Privileged role (admin/responder) required to access pending markers',
          details: []
        }
      });
    }

    const markers = db.getPendingMarkers();
    res.status(200).json({
      success: true,
      count: markers.length,
      data: markers
    });
  } catch (err) {
    next(err);
  }
}

function verify(req, res, next) {
  try {
    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    if (!isPrivileged) {
      return res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Privileged role (admin/responder) required to verify markers',
          details: []
        }
      });
    }

    const { id } = req.params;
    const { approve } = req.body;

    if (approve === undefined) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'approve (boolean) field is required',
          details: []
        }
      });
    }

    const existing = db.findMarkerById(id);
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'MARKER_NOT_FOUND',
          message: `Marker with ID ${id} not found`,
          details: []
        }
      });
    }

    const updated = db.verifyMarker(id, {
      approve: Boolean(approve),
      verifiedBy: req.user.id || req.user.name || 'admin'
    });

    res.status(200).json({
      success: true,
      message: Boolean(approve) ? 'Marker verified and published' : 'Marker rejected',
      data: updated
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
  pending,
  verify,
  getById
};
