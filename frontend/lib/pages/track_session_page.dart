import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';

/// Guardian-facing live tracking viewer.
///
/// The broadcaster shares a link of the form
/// `<base>/?session=<id>&token=<token>`; the guardian pastes it here. The
/// session token IS the credential — no SafeSphere account is required.
/// Live updates arrive over the `/ws/sos` tracking room; a REST poll runs in
/// parallel so a dropped socket degrades to polling instead of silence.
class TrackSessionPage extends StatefulWidget {
  const TrackSessionPage({super.key});

  @override
  State<TrackSessionPage> createState() => _TrackSessionPageState();
}

class _TrackSessionPageState extends State<TrackSessionPage> {
  final _linkController = TextEditingController();

  bool _watching = false;
  bool _connecting = false;
  String? _sessionId;
  String? _sessionToken;
  String? _error;

  String _status = 'unknown';
  String _userName = '';
  double? _lat;
  double? _lng;
  double? _accuracy;
  DateTime? _lastUpdate;
  int _breadcrumbCount = 0;
  final List<Map<String, dynamic>> _breadcrumbs = [];
  String? _expiresAt;
  bool _live = false;
  bool _stallDetected = false;
  bool _signalRestored = false;
  int _stalledDurationSeconds = 0;
  String? _checkInDeadline;
  int _missedCheckIns = 0;
  bool _checkInMissed = false;

  WebSocket? _ws;
  Timer? _pollTimer;

  static String get _wsUrl {
    final uri = Uri.parse(AuthService.apiBaseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '$wsScheme://${uri.host}$portPart/ws/sos';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ws?.close();
    _linkController.dispose();
    super.dispose();
  }

  /// Accepts a pasted share link, or bare `sessionId` + `token` text.
  /// Returns null and sets [_error] on unparseable input.
  Map<String, String>? _parseLink(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri != null) {
      final session = uri.queryParameters['session'] ?? uri.queryParameters['sessionId'];
      final token = uri.queryParameters['token'];
      if (session != null && token != null) {
        return {'sessionId': session, 'token': token};
      }
    }

    // Fallback: "<sessionId> <token>" or "<sessionId>:<token>"
    final parts = text.split(RegExp(r'[\s:]+')).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return {'sessionId': parts[0], 'token': parts[1]};
    }
    return null;
  }

  Future<void> _startWatching() async {
    final parsed = _parseLink(_linkController.text);
    if (parsed == null) {
      if (!mounted) return;
      setState(() => _error = 'Could not read a tracking link. Paste the full link the sender shared.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _connecting = true;
      _error = null;
      _watching = true;
      _sessionId = parsed['sessionId'];
      _sessionToken = parsed['token'];
    });

    await _connectWs();
    await _pollOnce();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollOnce());

    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _connectWs() async {
    try {
      final ws = await WebSocket.connect(_wsUrl).timeout(const Duration(seconds: 5));
      _ws = ws;
      ws.listen(
        (event) {
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;
            _handleWsMessage(msg);
          } catch (_) {}
        },
        onDone: () {
          if (mounted) setState(() => _live = false);
        },
        onError: (_) {
          if (mounted) setState(() => _live = false);
        },
      );
      ws.add(jsonEncode({
        'type': 'SUBSCRIBE_TRACKING',
        'sessionId': _sessionId,
        'token': _sessionToken,
      }));
      if (mounted) setState(() => _live = true);
    } catch (_) {
      // WS unavailable — REST polling below still keeps the view live.
      if (mounted) setState(() => _live = false);
    }
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    switch (msg['type']) {
      case 'TRACKING_SNAPSHOT':
        final session = msg['session'];
        if (session is Map<String, dynamic>) {
          if (!mounted) return;
          setState(() => _applySession(session));
        }
        break;
      case 'LOCATION_STREAM_UPDATE':
        if (!mounted) return;
        setState(() {
          if (_stallDetected) {
            _stallDetected = false;
            _signalRestored = true;
          }
          _checkInMissed = false;
          _missedCheckIns = 0;
          _lat = (msg['latitude'] as num?)?.toDouble();
          _lng = (msg['longitude'] as num?)?.toDouble();
          _accuracy = (msg['accuracy'] as num?)?.toDouble();
          _lastUpdate = DateTime.tryParse(msg['timestamp'] as String? ?? '') ?? DateTime.now();
          if (_lat != null && _lng != null) {
            _breadcrumbs.insert(0, {
              'latitude': _lat,
              'longitude': _lng,
              'accuracy': _accuracy,
              'timestamp': msg['timestamp'] ?? DateTime.now().toIso8601String(),
              'speed': msg['speed'],
              'battery': msg['battery'],
            });
            if (_breadcrumbs.length > 100) {
              _breadcrumbs.removeRange(100, _breadcrumbs.length);
            }
          }
          _breadcrumbCount = _breadcrumbs.isNotEmpty ? _breadcrumbs.length : (_breadcrumbCount + 1);
        });
        break;
      case 'CHECKIN_MISSED':
        if (!mounted) return;
        setState(() {
          _checkInMissed = true;
          _missedCheckIns = (msg['missedCheckIns'] as num?)?.toInt() ?? (_missedCheckIns + 1);
          if (msg['checkInDeadline'] != null) {
            _checkInDeadline = msg['checkInDeadline'] as String?;
          }
        });
        break;
      case 'STREAM_TERMINATE':
        if (!mounted) return;
        setState(() {
          _status = 'ended';
          _live = false;
        });
        _pollTimer?.cancel();
        break;
      case 'ERROR':
        if (!mounted) return;
        setState(() {
          _error = msg['message'] as String? ?? 'Tracking channel error';
          _live = false;
        });
        break;
    }
  }

  Future<void> _pollOnce() async {
    if (_sessionId == null || _sessionToken == null) return;
    final data = await AuthService.instance.fetchTrackingSession(
      sessionId: _sessionId!,
      trackingToken: _sessionToken!,
    );
    if (data == null) {
      if (mounted) {
        setState(() {
          _error = 'Session not found, expired, or link invalid.';
          _status = 'unavailable';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _error = null;
        _applySession(data);
      });
    }
  }

  void _applySession(Map<String, dynamic> data) {
    _status = data['status'] as String? ?? _status;
    _userName = data['userName'] as String? ?? _userName;
    _expiresAt = data['expiresAt'] as String?;
    final crumbs = data['breadcrumbs'];
    if (crumbs is List) {
      _breadcrumbs.clear();
      for (final c in crumbs) {
        if (c is Map<String, dynamic>) {
          _breadcrumbs.add(Map<String, dynamic>.from(c));
        }
      }
      _breadcrumbs.sort((a, b) {
        final tA = a['timestamp'] as String? ?? '';
        final tB = b['timestamp'] as String? ?? '';
        return tB.compareTo(tA);
      });
      if (_breadcrumbs.length > 100) {
        _breadcrumbs.removeRange(100, _breadcrumbs.length);
      }
      _breadcrumbCount = _breadcrumbs.length;
    }
    final loc = data['currentLocation'];
    if (loc is Map<String, dynamic>) {
      _lat = (loc['latitude'] as num?)?.toDouble();
      _lng = (loc['longitude'] as num?)?.toDouble();
      _accuracy = (loc['accuracy'] as num?)?.toDouble();
    }
    _lastUpdate = DateTime.now();

    final bool prevStall = _stallDetected;
    final dynamic rawStall = data['stallDetected'] ?? (data['session'] is Map ? data['session']['stallDetected'] : null);
    final bool newStall = rawStall == true;
    final dynamic rawDuration = data['stalledDurationSeconds'] ?? (data['session'] is Map ? data['session']['stalledDurationSeconds'] : null);
    final int stalledSec = (rawDuration as num?)?.toInt() ?? 0;

    if (_status == 'active') {
      if (prevStall && !newStall) {
        _signalRestored = true;
        _stallDetected = false;
      } else if (_signalRestored && !newStall) {
        _signalRestored = false;
      } else if (newStall) {
        _stallDetected = true;
        _signalRestored = false;
      } else {
        _stallDetected = false;
      }
    } else {
      _stallDetected = false;
      _signalRestored = false;
    }
    _stalledDurationSeconds = stalledSec;

    final rawDeadline = data['checkInDeadline'] ?? (data['session'] is Map ? data['session']['checkInDeadline'] : null);
    _checkInDeadline = rawDeadline as String?;

    final rawMissed = data['missedCheckIns'] ?? (data['session'] is Map ? data['session']['missedCheckIns'] : null);
    _missedCheckIns = (rawMissed as num?)?.toInt() ?? 0;
    if (_missedCheckIns > 0) {
      _checkInMissed = true;
    } else {
      _checkInMissed = false;
    }

    if (_status == 'expired' || _status == 'ended') {
      _pollTimer?.cancel();
      _live = false;
      _stallDetected = false;
      _signalRestored = false;
      _checkInMissed = false;
    }
  }

  bool get _isExpiringSoon {
    if (_expiresAt == null || _status != 'active') return false;
    final expiry = DateTime.tryParse(_expiresAt!);
    if (expiry == null) return false;
    final now = DateTime.now();
    return expiry.isAfter(now) && expiry.isBefore(now.add(const Duration(minutes: 5)));
  }

  void _stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ws?.close();
    _ws = null;
    if (!mounted) return;
    setState(() {
      _watching = false;
      _live = false;
      _sessionId = null;
      _sessionToken = null;
      _status = 'unknown';
      _userName = '';
      _lat = null;
      _lng = null;
      _breadcrumbCount = 0;
      _breadcrumbs.clear();
      _stallDetected = false;
      _signalRestored = false;
      _stalledDurationSeconds = 0;
      _checkInDeadline = null;
      _missedCheckIns = 0;
      _checkInMissed = false;
    });
  }

  Future<void> _openMaps() async {
    if (_lat == null || _lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps?q=$_lat,$_lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Live Trip'),
        actions: [
          if (_watching)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop watching',
              onPressed: _stopWatching,
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: !_watching ? _buildJoinForm() : _buildLiveView(),
        ),
      ),
    );
  }

  Widget _buildJoinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste the SafeSphere tracking link you received. No account needed — the link itself is the credential.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _linkController,
          decoration: const InputDecoration(
            labelText: 'Tracking link or session credentials',
            hintText: 'https://…/?session=…&token=…',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          onSubmitted: (_) => _startWatching(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _connecting ? null : _startWatching,
          icon: _connecting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location),
          label: Text(_connecting ? 'Connecting…' : 'Watch Live Location'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
      ],
    );
  }

  Widget _buildLiveView() {
    final statusColor = switch (_status) {
      'active' => AppColors.teal,
      'ended' => AppColors.amber,
      'expired' => AppColors.amber,
      _ => AppColors.textSecondary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 8),
            Text(
              '${_status.toUpperCase()}${_live ? ' · LIVE' : ''}',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy session credentials',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '$_sessionId $_sessionToken'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Session credentials copied')),
                );
              },
            ),
          ],
        ),
        if (_userName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tracking: $_userName',
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        if (_stallDetected && _status == 'active') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber),
            ),
            child: Row(
              children: [
                const Icon(Icons.signal_wifi_off_rounded, color: AppColors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SIGNAL LOST — no update for ${(_stalledDurationSeconds ~/ 60) > 0 ? (_stalledDurationSeconds ~/ 60) : 2}m',
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_signalRestored && !_stallDetected && _status == 'active') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.teal),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.teal, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Signal restored',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if ((_checkInMissed || _missedCheckIns > 0) && _status == 'active') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CHECK-IN MISSED — User has not checked in (${_missedCheckIns} missed)',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isExpiringSoon) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Session expires soon",
                    style: TextStyle(
                      color: AppColors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const Divider(color: AppColors.border),
        Expanded(
          child: ListView(
            children: [
              _infoTile('Last known position',
                  _lat != null ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}' : 'Awaiting first fix'),
              _infoTile('Accuracy',
                  _accuracy != null ? '±${_accuracy!.toStringAsFixed(0)} m' : '—'),
              _infoTile('Breadcrumbs received', '$_breadcrumbCount'),
              _infoTile('Last update',
                  _lastUpdate != null ? _lastUpdate!.toLocal().toString().substring(0, 19) : '—'),
              _infoTile('Session expires', _expiresAt ?? '—'),
              if (_checkInDeadline != null) ...[
                () {
                  final parsed = DateTime.tryParse(_checkInDeadline!);
                  final dueStr = parsed != null
                      ? '${parsed.toLocal().hour.toString().padLeft(2, '0')}:${parsed.toLocal().minute.toString().padLeft(2, '0')}'
                      : _checkInDeadline!;
                  return _infoTile('Next check-in due', dueStr);
                }(),
              ],
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.route, size: 20, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Text(
                    'Recent Breadcrumb Trail (${_breadcrumbs.length} points)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_breadcrumbs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No breadcrumb positions recorded yet. Live updates will appear here.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                )
              else
                ..._breadcrumbs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final pt = entry.value;
                  final lat = (pt['latitude'] as num?)?.toDouble();
                  final lng = (pt['longitude'] as num?)?.toDouble();
                  final acc = (pt['accuracy'] as num?)?.toDouble();
                  final rawTime = pt['timestamp'] as String? ?? '';
                  final timeParsed = DateTime.tryParse(rawTime);
                  final timeStr = timeParsed != null
                      ? timeParsed.toLocal().toString().substring(11, 19)
                      : (rawTime.isNotEmpty ? rawTime : '—');
                  final isLatest = index == 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLatest
                          ? AppColors.teal.withOpacity(0.08)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isLatest ? AppColors.teal.withOpacity(0.3) : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: isLatest ? AppColors.teal : Colors.grey.shade700,
                          child: Text(
                            isLatest ? '★' : '#${_breadcrumbs.length - index}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lat != null && lng != null
                                    ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                                    : 'Unknown coords',
                                style: TextStyle(
                                  fontWeight: isLatest ? FontWeight.bold : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Time: $timeStr',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (acc != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '±${acc.toStringAsFixed(0)} m',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.teal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              if (_lat != null && _lng != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openMaps,
                  icon: const Icon(Icons.map),
                  label: const Text('Open last position in Google Maps'),
                ),
              ],
              if (_status == 'ended' || _status == 'expired') ...[
                const SizedBox(height: 12),
                const Text(
                  'This tracking session has ended. The path shown is the final recorded trail.',
                  style: TextStyle(color: AppColors.amber),
                ),
              ],
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.red)),
          ),
      ],
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}
