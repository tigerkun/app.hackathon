import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';

class ShareLocationPage extends StatefulWidget {
  const ShareLocationPage({super.key});

  @override
  State<ShareLocationPage> createState() => _ShareLocationPageState();
}

class _ShareLocationPageState extends State<ShareLocationPage> {
  // ── GPS state ──────────────────────────────────────────────────────────────
  bool _isLoading = false;
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  DateTime? _lastUpdated;

  // ── Live tracking session state ────────────────────────────────────────────
  bool _isTracking = false;
  bool _isStartingSession = false;
  String? _sessionId;
  String? _sessionToken;
  String? _shareUrl;
  String? _expiresAt;
  int? _checkInIntervalMin;
  int _pingCount = 0;

  Timer? _pingTimer;
  StreamSubscription<Position>? _positionStream;
  WebSocket? _ws;

  // ── Backend base URL (matches AuthService) ─────────────────────────────────
  static const String _backendBase = AuthService.apiBaseUrl;
  static String get _wsUrl {
    final uri = Uri.parse(AuthService.apiBaseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '$wsScheme://${uri.host}$portPart/ws/sos';
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _stopTracking(notify: false);
    super.dispose();
  }

  // ── GPS Acquisition ────────────────────────────────────────────────────────
  Future<void> _fetchCurrentLocation() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    double? lat, lng, acc;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }

        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 6),
              ),
            ).timeout(const Duration(seconds: 7));
          } catch (_) {
            pos = await Geolocator.getLastKnownPosition();
          }

          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            acc = pos.accuracy;
          }
        }
      }
    } catch (_) {}

    if (lat == null || lng == null) {
      final loc = LocationService.instance;
      if (loc.hasLiveGps || loc.isManualOverride) {
        lat = loc.currentLat;
        lng = loc.currentLng;
      }
    }

    if (mounted) {
      setState(() {
        _latitude = lat;
        _longitude = lng;
        _accuracy = acc;
        _lastUpdated = lat != null ? DateTime.now() : null;
        _isLoading = false;
      });
    }
  }

  // ── Start Live Tracking Session ────────────────────────────────────────────
  Future<void> _startLiveTracking() async {
    if (_latitude == null || _longitude == null) {
      await _fetchCurrentLocation();
    }
    if (_latitude == null || _longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cannot start tracking: GPS unavailable. Enable device location."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _isStartingSession = true);
    String? createdSessionId;
    String? createdSessionToken;

    try {
      // 1. Create backend tracking session via AuthService
      final sessionData = await AuthService.instance.createTrackingSession(
        latitude: _latitude!,
        longitude: _longitude!,
        accuracy: _accuracy,
        durationMinutes: 60,
        checkInIntervalMin: _checkInIntervalMin,
      );

      if (sessionData == null) {
        throw Exception('Backend rejected session creation');
      }

      final sessionId = sessionData['sessionId'] as String;
      final sessionToken = sessionData['token'] as String;
      createdSessionId = sessionId;
      createdSessionToken = sessionToken;

      // M6 orphan guard: if the page was disposed while the session was being
      // created, the backend now holds a LIVE tracking session nobody is
      // watching — terminate it immediately instead of leaking it.
      if (!mounted) {
        await AuthService.instance.terminateTrackingSession(
          sessionId: sessionId,
          trackingToken: sessionToken,
          reason: 'Share page closed during session setup',
        );
        return;
      }
      final shareUrl = sessionData['shareUrl'] as String? ?? 'https://www.google.com/maps?q=$_latitude,$_longitude';
      final expiresAt = sessionData['expiresAt'] as String?;

      // 2. Connect to WebSocket channel for real-time relay
      final ws = await WebSocket.connect(_wsUrl)
          .timeout(const Duration(seconds: 5));

      // M6 dispose-race guard: if the page was disposed while connecting,
      // close the socket immediately instead of leaking it (the setState
      // block below is skipped when unmounted, so _ws is never assigned).
      if (!mounted) {
        await ws.close().catchError((_) {});
        await AuthService.instance.terminateTrackingSession(
          sessionId: sessionId,
          trackingToken: sessionToken,
          reason: 'Share page closed during session setup',
        );
        return;
      }

      // 3. Every tracking WebSocket frame and REST call is authenticated with the
      //    session token issued above (the token IS the credential — see below).

      if (mounted) {
        setState(() {
          _sessionId = sessionId;
          _sessionToken = sessionToken;
          _shareUrl = shareUrl;
          _expiresAt = expiresAt;
          _isTracking = true;
          _isStartingSession = false;
          _pingCount = 0;
          _ws = ws;
        });
      }

      // 4. Start continuous GPS stream and periodic 30-second REST ping
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((Position pos) {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _accuracy = pos.accuracy;
        _lastUpdated = DateTime.now();
        if (mounted) setState(() {});
      });

      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendLocationPing();
      });
      createdSessionId = null;
      createdSessionToken = null;

      // 5. Share the tracking URL immediately via SMS/messaging. The URL carries
      //    the session token (the credential) — the guardian pastes it into
      //    SafeSphere → "Watch Live Trip".
      await Share.share(
        '📍 [SafeSphere Live Tracking] I am sharing my real-time location for safety.\n'
        'Track me: open SafeSphere → "Watch Live Trip" and paste this link:\n$shareUrl',
      );
    } catch (e) {
      var cleanupFailed = false;
      if (createdSessionId != null && createdSessionToken != null) {
        cleanupFailed = !await AuthService.instance.terminateTrackingSession(
          sessionId: createdSessionId,
          trackingToken: createdSessionToken,
          reason: 'Live tracking setup failed',
        );
      }
      if (mounted) {
        setState(() => _isStartingSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not start live tracking session: $e'
              '${cleanupFailed ? '. The session may still be active.' : ''}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── Send a GPS breadcrumb ping ─────────────────────────────────────────────
  Future<void> _sendLocationPing() async {
    if (_sessionId == null || _latitude == null || _longitude == null || _sessionToken == null) return;

    // TODO(REAL_BACKEND): WS broadcast persists the breadcrumb server-side AND
    // relays it to subscribed guardians in real time. When the socket is down we
    // fall back to a REST ping so breadcrumbs keep flowing — never both, or every
    // point is persisted twice.
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      try {
        _ws!.add(jsonEncode({
          'type': 'LOCATION_STREAM_UPDATE',
          'sessionId': _sessionId,
          'token': _sessionToken,
          'latitude': _latitude,
          'longitude': _longitude,
          'accuracy': _accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        }));
      } catch (_) {}
    } else {
      try {
        await AuthService.instance.sendLocationPing(
          sessionId: _sessionId!,
          latitude: _latitude!,
          longitude: _longitude!,
          trackingToken: _sessionToken!,
          accuracy: _accuracy,
        );
      } catch (_) {}
    }

    if (mounted) setState(() => _pingCount++);
  }

  // ── Stop & terminate tracking session ─────────────────────────────────────
  Future<void> _stopTracking({bool notify = true}) async {
    _pingTimer?.cancel();
    _pingTimer = null;

    await _positionStream?.cancel();
    _positionStream = null;

    final sessId = _sessionId;
    final sessToken = _sessionToken;

    if (sessId != null) {
      // Notify WebSocket channel
      try {
        _ws?.add(jsonEncode({
          'type': 'STREAM_TERMINATE',
          'sessionId': sessId,
          'token': sessToken,
          'reason': 'User ended tracking session',
        }));
      } catch (_) {}

      // Terminate via REST for server-side cleanup via AuthService
      try {
        if (sessToken != null) {
          await AuthService.instance.terminateTrackingSession(
            sessionId: sessId,
            trackingToken: sessToken,
            reason: 'User ended tracking session',
          );
        }
      } catch (_) {}
    }

    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;

    if (mounted) {
      setState(() {
        _isTracking = false;
        _sessionId = null;
        _sessionToken = null;
        _shareUrl = null;
        _expiresAt = null;
        _pingCount = 0;
      });
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Live tracking session ended. Session watchers notified."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  bool get _isExpiringSoon {
    if (_expiresAt == null || !_isTracking) return false;
    final expiry = DateTime.tryParse(_expiresAt!);
    if (expiry == null) return false;
    final now = DateTime.now();
    return expiry.isAfter(now) && expiry.isBefore(now.add(const Duration(minutes: 5)));
  }

  // ── One-shot static share (no live session) ────────────────────────────────
  Future<void> _shareStaticLocation() async {
    if (_latitude == null || _longitude == null) {
      await _fetchCurrentLocation();
    }
    if (_latitude == null || _longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("GPS unavailable — cannot share location."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    final url = 'https://www.google.com/maps?q=$_latitude,$_longitude';
    await Share.share('🚨 [SafeSphere] My current location:\n$url');
  }

  Future<void> _openGoogleMaps() async {
    if (_latitude == null || _longitude == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final latStr = _latitude != null ? _latitude!.toStringAsFixed(5) : '—';
    final lngStr = _longitude != null ? _longitude!.toStringAsFixed(5) : '—';
    final accStr = _accuracy != null ? '±${_accuracy!.toStringAsFixed(1)}m' : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Share Location"),
        actions: [
          if (!_isTracking)
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _fetchCurrentLocation,
              tooltip: "Refresh GPS",
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── GPS Status Card ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF101A33),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (_latitude == null
                      ? Colors.redAccent
                      : _isTracking
                          ? Colors.greenAccent
                          : AppColors.teal)
                      .withOpacity(0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _latitude == null ? Icons.location_off : Icons.gps_fixed,
                            color: _latitude == null
                                ? Colors.redAccent
                                : _isTracking ? Colors.greenAccent : AppColors.teal,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _latitude == null
                                ? "GPS Unavailable"
                                : _isTracking
                                    ? "Live Tracking Active"
                                    : "High-Accuracy GPS",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_isTracking ? Colors.greenAccent : AppColors.teal).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isLoading
                              ? "Acquiring..."
                              : _isTracking
                                  ? "LIVE • $_pingCount pings"
                                  : _latitude != null ? "Ready" : "No Signal",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isTracking ? Colors.greenAccent : AppColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Latitude", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(latStr,
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Longitude", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(lngStr,
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Accuracy: $accStr", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      if (_lastUpdated != null)
                        Text(
                          "Updated: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  ),

                  // Session info when active
                  if (_isTracking && _sessionId != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    Row(
                      children: [
                        const Icon(Icons.link, size: 14, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Session: $_sessionId",
                            style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_expiresAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.white54),
                          const SizedBox(width: 6),
                          Text(
                            "Expires: $_expiresAt",
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                      if (_isExpiringSoon) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.amber),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Session expires soon",
                                  style: TextStyle(
                                    color: AppColors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    if (_shareUrl != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shareUrl!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.teal,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16, color: AppColors.teal),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: "Copy tracking link",
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _shareUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Tracking link copied to clipboard")),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Map Visualizer ────────────────────────────────────────────
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _isTracking ? Colors.greenAccent.withOpacity(0.4) : Colors.white24),
                color: const Color(0xFF0D1526),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _LocationGridPainter(isActive: _isTracking))),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: (_isTracking ? Colors.greenAccent : AppColors.teal).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              _isTracking ? Icons.radio_button_checked : Icons.my_location,
                              color: _isTracking ? Colors.greenAccent : AppColors.teal,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (_isTracking ? Colors.greenAccent : AppColors.teal).withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            _isTracking
                                ? "Broadcasting to guardians · $_pingCount pings sent"
                                : _latitude != null ? "Live Coordinates Detected" : "Awaiting GPS Signal",
                            style: TextStyle(
                              fontSize: 11,
                              color: _isTracking ? Colors.greenAccent : AppColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14, color: AppColors.blue),
                      label: const Text("Open Map", style: TextStyle(fontSize: 11, color: AppColors.blue)),
                      onPressed: _openGoogleMaps,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (!_isTracking) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101A33),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 18, color: AppColors.teal),
                        SizedBox(width: 8),
                        Text(
                          "Check-in timer (dead-man switch)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "alerts monitoring clients & session watchers",
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text("Off"),
                          selected: _checkInIntervalMin == null,
                          onSelected: (selected) {
                            if (selected) setState(() => _checkInIntervalMin = null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("15 min"),
                          selected: _checkInIntervalMin == 15,
                          onSelected: (selected) {
                            if (selected) setState(() => _checkInIntervalMin = 15);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("30 min"),
                          selected: _checkInIntervalMin == 30,
                          onSelected: (selected) {
                            if (selected) setState(() => _checkInIntervalMin = 30);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("60 min"),
                          selected: _checkInIntervalMin == 60,
                          onSelected: (selected) {
                            if (selected) setState(() => _checkInIntervalMin = 60);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Primary Action: Start / Stop Live Tracking ────────────────
            if (!_isTracking)
              ElevatedButton.icon(
                icon: _isStartingSession
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.share_location, color: Colors.black),
                label: Text(
                  _isStartingSession ? "Starting session…" : "Start Live Tracking Session",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: (_isLoading || _isStartingSession) ? null : _startLiveTracking,
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                label: const Text("Stop Live Tracking", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _stopTracking(),
              ),

            const SizedBox(height: 12),

            // ── Secondary: static one-shot share ─────────────────────────
            OutlinedButton.icon(
              icon: const Icon(Icons.send, color: AppColors.blue),
              label: const Text("Share Current Location (One-shot)", style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.blue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isTracking ? null : _shareStaticLocation,
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.navigation, color: Colors.white60),
              label: const Text("Open in Google Maps", style: TextStyle(color: Colors.white60)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _openGoogleMaps,
            ),

            if (_isTracking) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Guardians with your share link are receiving your real-time location every 10 seconds via the SafeSphere WebSocket channel.",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationGridPainter extends CustomPainter {
  final bool isActive;
  const _LocationGridPainter({this.isActive = false});

  @override
  void paint(Canvas canvas, Size size) {
    final gridColor = isActive ? const Color(0x1A69FF8C) : const Color(0x1A2FE0C9);
    final paint = Paint()..color = gridColor..strokeWidth = 1;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final circlePaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 40, circlePaint);
    canvas.drawCircle(center, 80, circlePaint);
  }

  @override
  bool shouldRepaint(covariant _LocationGridPainter old) => old.isActive != isActive;
}
