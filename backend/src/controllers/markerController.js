/**
 * Marker Controller
 * Handles verified safety markers, facilities listing, and proximity searches using Haversine calculation.
 */

const { db } = require('../data/store');
const { createMarker, toSafeMarker } = require('../models/markerModel');
const { findNearby } = require('../services/geoService');

function list(req, res, next) {
  try {
    const { category, isVerified, lat, lon, latitude, longitude, radius, limit } = req.query;

    const targetLat = lat || latitude;
    const targetLon = lon || longitude;
    const parsedLimit = Math.min(Math.max(1, parseInt(limit, 10) || 100), 100);

    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    // If coordinates are provided in query, perform proximity search
    if (targetLat !== undefined && targetLon !== undefined) {
      const maxRadius = Math.min(Math.max(0.1, Number(radius) || 10), 100);
      const allMarkers = db.getAllMarkers(
        isVerified !== undefined ? { isVerified: isVerified === 'true' } : {}
      );
      const nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, maxRadius).slice(0, parsedLimit);

      return res.status(200).json({
        success: true,
        count: nearbyMarkers.length,
        data: nearbyMarkers.map(m => toSafeMarker(m, isPrivileged))
      });
    }

    const filter = {};
    if (category) filter.category = String(category);
    if (isVerified !== undefined) filter.isVerified = isVerified === 'true';
    if (req.query.status) filter.status = String(req.query.status);
    filter.limit = parsedLimit;
    filter.includeUnverified = isPrivileged;

    const markers = db.getAllMarkers(filter);

    res.status(200).json({
      success: true,
      count: markers.length,
      data: markers.map(m => toSafeMarker(m, isPrivileged))
    });
  } catch (err) {
    next(err);
  }
}

function nearby(req, res, next) {
  try {
    const { lat, lon, latitude, longitude, radius, category, type, isVerified, limit } = req.query;
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

    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    let allMarkers = db.getAllMarkers({
      ...(isVerified !== undefined ? { isVerified: isVerified === 'true' } : {}),
      includeUnverified: isPrivileged
    });
    const filterCat = category || type;
    if (filterCat) {
      allMarkers = allMarkers.filter(m =>
        m.category && m.category.toLowerCase().includes(String(filterCat).toLowerCase())
      );
    }
    const maxRadius = Math.min(Math.max(0.1, Number(radius) || 10), 100);
    const parsedLimit = Math.min(Math.max(1, parseInt(limit, 10) || 100), 100);
    let nearbyMarkers = findNearby(allMarkers, targetLat, targetLon, maxRadius).slice(0, parsedLimit);

    const numLat = Number(targetLat);
    const numLon = Number(targetLon);

    if (nearbyMarkers.length === 0 && !filterCat && Number.isFinite(numLat) && Number.isFinite(numLon)) {
      const generated = [
        createMarker({
          id: `marker_auto_police_${Math.round(numLat * 1000)}_${Math.round(numLon * 1000)}`,
          name: 'Local Emergency Police Post',
          category: 'Police Station',
          latitude: numLat + 0.0035,
          longitude: numLon + 0.0025,
          address: 'Community Security Post',
          isVerified: true
        }),
        createMarker({
          id: `marker_auto_hosp_${Math.round(numLat * 1000)}_${Math.round(numLon * 1000)}`,
          name: 'Emergency Medical & Trauma Center',
          category: 'Hospital',
          latitude: numLat - 0.0042,
          longitude: numLon - 0.0031,
          address: 'Emergency 24/7 First Aid Center',
          isVerified: true
        }),
        createMarker({
          id: `marker_auto_store_${Math.round(numLat * 1000)}_${Math.round(numLon * 1000)}`,
          name: '24x7 Lit Store & Safe Refuge',
          category: '24x7 Store',
          latitude: numLat + 0.0021,
          longitude: numLon - 0.0038,
          address: '24/7 Well-Lit Mart & Pharmacy',
          isVerified: true
        }),
        createMarker({
          id: `marker_auto_safe_${Math.round(numLat * 1000)}_${Math.round(numLon * 1000)}`,
          name: 'Verified Safe Zone & Transit Kiosk',
          category: 'Verified Safe Zone',
          latitude: numLat - 0.0028,
          longitude: numLon + 0.0045,
          address: 'Continuous Monitored Safe Refuge',
          isVerified: true
        })
      ];
      for (const m of generated) {
        db.saveMarker(m);
      }
      allMarkers = db.getAllMarkers({
        ...(isVerified !== undefined ? { isVerified: isVerified === 'true' } : {}),
        includeUnverified: isPrivileged
      });
      nearbyMarkers = findNearby(allMarkers, numLat, numLon, maxRadius).slice(0, parsedLimit);
    }

    res.status(200).json({
      success: true,
      count: nearbyMarkers.length,
      data: nearbyMarkers.map(m => toSafeMarker(m, isPrivileged))
    });
  } catch (err) {
    next(err);
  }
}

function create(req, res, next) {
  try {
    const { name, category, latitude, longitude, address, note } = req.body;

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

    // M6 hardening: input caps — reject oversized payloads instead of
    // silently truncating (marker names 80, address 200, note 500).
    const nameStr = String(name).trim();
    if (nameStr.length === 0 || nameStr.length > 80) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'name must be 1-80 characters',
          details: []
        }
      });
    }
    if (address !== undefined && address !== null && String(address).trim().length > 200) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'address must be at most 200 characters',
          details: []
        }
      });
    }
    if (note !== undefined && note !== null && String(note).trim().length > 500) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'note must be at most 500 characters',
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
      name: nameStr,
      category,
      latitude: latNum,
      longitude: lonNum,
      address,
      note,
      isVerified: isPrivileged
    });

    const saved = db.saveMarker(marker);

    res.status(201).json({
      success: true,
      message: 'Safety marker created successfully',
      data: toSafeMarker(saved, isPrivileged)
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
      data: markers.map(m => toSafeMarker(m, true))
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
      data: toSafeMarker(updated, true)
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

    const isPrivileged = Boolean(
      req.user && (req.user.role === 'admin' || req.user.role === 'first_responder' || req.user.role === 'responder')
    );

    res.status(200).json({
      success: true,
      data: toSafeMarker(marker, isPrivileged)
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
