/**
 * Geo Service
 * Haversine great-circle distance math and spatial proximity filtering.
 */

function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Calculates Haversine distance in kilometers between two coordinates.
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371.0; // Earth's mean radius in km
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 1000) / 1000; // 3 decimal places
}

/**
 * Filters and sorts items with coordinates within specified radius in km.
 */
function findNearby(items, targetLat, targetLon, radiusKm = 10) {
  const tLat = Number(targetLat);
  const tLon = Number(targetLon);
  const rad = Number(radiusKm);

  if (isNaN(tLat) || isNaN(tLon)) {
    return [];
  }

  const results = [];
  for (const item of items) {
    if (item.latitude !== null && item.longitude !== null && !isNaN(item.latitude) && !isNaN(item.longitude)) {
      const distance = calculateDistance(tLat, tLon, item.latitude, item.longitude);
      if (distance <= rad) {
        results.push({
          ...item,
          distanceKm: distance
        });
      }
    }
  }

  return results.sort((a, b) => a.distanceKm - b.distanceKm);
}

module.exports = {
  calculateDistance,
  findNearby
};
