/// M4: Movement Analyzer — breadcrumb state machine.
///
/// Turns a stream of breadcrumb fixes (latitude, longitude, timestamp, speed)
/// into a plain-language movement state a worried guardian can act on:
///   stationary → moving → (heading somewhere) → stalled → stationary
///
/// Design rules:
/// - Honest: it reports what the data shows, nothing more ("stationary for
///   12 min", "moving ~18 km/h"). It NEVER claims to know intent ("at home",
///   "safe") — only what the telemetry supports.
/// - Tolerant: empty lists, single points, malformed entries all degrade to
///   an explicit "unknown" state rather than throwing.
/// - Zero third-party dependencies: pure Dart, testable headless.
library;

import 'dart:math' as math show sin, cos, sqrt, atan2;

class MovementState {
  /// One of: unknown | stationary | moving | stalled
  final String state;

  /// Plain-language line for a guardian UI, e.g.
  /// "Moving at ~18 km/h" / "Stationary for 12 min" / "Signal lost — no
  /// update for 6 min".
  final String summary;

  /// Mean speed in km/h over the analysis window (null when unknown).
  final double? speedKmh;

  /// Seconds since the newest breadcrumb (null when timestamps are absent).
  final int? secondsSinceLastUpdate;

  /// Bearing of the last two points in degrees 0-359 (null when not enough
  /// points or not moving).
  final double? headingDeg;

  /// Compass label for [headingDeg] (north, northeast, …).
  final String? headingLabel;

  const MovementState({
    required this.state,
    required this.summary,
    this.speedKmh,
    this.secondsSinceLastUpdate,
    this.headingDeg,
    this.headingLabel,
  });
}

class MovementAnalyzer {
  /// Below this speed (km/h) the subject counts as stationary (GPS jitter).
  static const double stationarySpeedKmh = 1.5;

  /// Above this gap with no new breadcrumbs, the subject counts as stalled —
  /// matches the F3-2 backend stall window (120s).
  static const Duration stallWindow = Duration(seconds: 120);

  /// Minimum displacement (metres) between fixes for a movement segment.
  static const double minDisplacementM = 10;

  /// Analyzes chronologically ordered breadcrumbs (oldest → newest).
  /// Each entry: { latitude, longitude, timestamp?, speed? (m/s) }.
  static MovementState analyze(List<dynamic> breadcrumbs, {DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final points = <_Fix>[];

    if (breadcrumbs != null) {
      for (final raw in breadcrumbs) {
        if (raw is Map) {
          final lat = _toDouble(raw['latitude']);
          final lng = _toDouble(raw['longitude']);
          if (lat == null || lng == null) continue;
          final ts = raw['timestamp'] != null
              ? DateTime.tryParse(raw['timestamp'].toString())
              : null;
          final speed = _toDouble(raw['speed']);
          points.add(_Fix(lat, lng, ts, speed));
        }
      }
    }

    if (points.isEmpty) {
      return const MovementState(
        state: 'unknown',
        summary: 'No location data yet — waiting for the first signal.',
      );
    }

    final newest = points.last;
    final secondsSince = newest.timestamp != null
        ? _clampSeconds(ref.difference(newest.timestamp!).inSeconds)
        : null;

    // Stall detection first — a stale feed overrides movement analysis.
    if (secondsSince != null && secondsSince > stallWindow.inSeconds) {
      final minutes = secondsSince ~/ 60;
      return MovementState(
        state: 'stalled',
        summary: 'Signal lost — no update for ${minutes >= 1 ? "$minutes min" : "$secondsSince s"}.',
        secondsSinceLastUpdate: secondsSince,
      );
    }

    // Not enough points for movement math → single-fix state.
    if (points.length < 2) {
      if (secondsSince != null && secondsSince > 90) {
        return MovementState(
          state: 'stationary',
          summary: 'One location fix, ${_fmtDuration(secondsSince)} ago — appears stationary.',
          secondsSinceLastUpdate: secondsSince,
        );
      }
      return const MovementState(
        state: 'unknown',
        summary: 'Waiting for a second location fix to detect movement.',
      );
    }

    // Aggregate movement over the trailing window (up to last 10 fixes).
    final window = points.length > 10 ? points.sublist(points.length - 10) : points;
    double distanceM = 0;
    int spanSeconds = 0;
    for (int i = 1; i < window.length; i++) {
      final a = window[i - 1];
      final b = window[i];
      if (a.timestamp == null || b.timestamp == null) continue;
      final segSeconds = b.timestamp!.difference(a.timestamp!).inSeconds;
      if (segSeconds <= 0 || segSeconds > 3600) continue; // ignore bogus gaps
      distanceM += _haversineM(a.lat, a.lng, b.lat, b.lng);
      spanSeconds += segSeconds;
    }

    final double? avgSpeedKmh = spanSeconds > 0 ? (distanceM / spanSeconds) * 3.6 : null;

    final heading = _headingDeg(window[window.length - 2], window.last);
    final headingInfo = avgSpeedKmh != null &&
            avgSpeedKmh >= stationarySpeedKmh &&
            heading != null
        ? _compassLabel(heading)
        : null;

    if (avgSpeedKmh != null && avgSpeedKmh >= stationarySpeedKmh && distanceM >= minDisplacementM) {
      return MovementState(
        state: 'moving',
        summary: 'Moving at ~${avgSpeedKmh.round()} km/h'
            '${headingInfo != null ? " heading $headingInfo" : ""}.',
        speedKmh: avgSpeedKmh,
        secondsSinceLastUpdate: secondsSince,
        headingDeg: heading,
        headingLabel: headingInfo,
      );
    }

    // Stationary: report dwell time from the last real movement.
    final dwell = _dwellSeconds(window, ref);
    return MovementState(
      state: 'stationary',
      summary: dwell != null
          ? 'Stationary for ${_fmtDuration(dwell)}'
              '${secondsSince != null && secondsSince > 60 ? " (last ping ${_fmtDuration(secondsSince)} ago)" : ""}.'
          : 'Not moving right now.',
      speedKmh: avgSpeedKmh,
      secondsSinceLastUpdate: secondsSince,
    );
  }

  /// Seconds the subject has been stationary, using the last fix that moved
  /// more than [minDisplacementM]. Null when the whole window is one place.
  static int? _dwellSeconds(List<_Fix> window, DateTime ref) {
    final last = window.last;
    if (last.timestamp == null) return null;
    for (int i = window.length - 2; i >= 0; i--) {
      final f = window[i];
      if (f.timestamp == null) continue;
      if (_haversineM(f.lat, f.lng, last.lat, last.lng) >= minDisplacementM) {
        final d = _clampSeconds(ref.difference(f.timestamp!).inSeconds);
        return d > 0 ? d : null;
      }
    }
    return null;
  }

  static int _clampSeconds(int s) => s.clamp(0, 86400 * 7);

  static double? _headingDeg(_Fix from, _Fix to) {
    final dx = to.lng - from.lng;
    final dy = to.lat - from.lat;
    if (dx == 0 && dy == 0) return null;
    final rad = math.atan2(dx, dy); // bearing from true north
    final deg = (rad * 180 / 3.141592653589793 + 360) % 360;
    return deg;
  }

  static String _compassLabel(double deg) {
    const dirs = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'];
    final idx = (((deg + 22.5) % 360) / 45).floor() % 8;
    return dirs[idx];
  }

  static String _fmtDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return '$hours h ${minutes % 60} min';
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = _sin2(dLat / 2) + _cosd(lat1) * _cosd(lat2) * _sin2(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double d) => d * 3.141592653589793 / 180;
  static double _sin2(double x) {
    final s = math.sin(x);
    return s * s;
  }

  static double _cosd(double deg) => math.cos(_deg2rad(deg));
}

class _Fix {
  final double lat;
  final double lng;
  final DateTime? timestamp;
  final double? speed;
  const _Fix(this.lat, this.lng, this.timestamp, this.speed);
}
