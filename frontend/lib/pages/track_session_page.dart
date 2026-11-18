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
  String? _expiresAt;
  bool _live = false;

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
      final session = uri.queryParameters['session'];
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
      setState(() => _error = 'Could not read a tracking link. Paste the full link the sender shared.');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
      _watching = true;
      _sessionId = parsed!['sessionId'];
      _sessionToken = parsed['token'];
    });

    await _connectWs();
    await _pollOnce();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollOnce());

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
    switch (msg['type']) {
      case 'TRACKING_SNAPSHOT':
        final session = msg['session'];
        if (session is Map<String, dynamic>) {
          setState(() => _applySession(session));
        }
        break;
      case 'LOCATION_STREAM_UPDATE':
        setState(() {
          _lat = (msg['latitude'] as num?)?.toDouble();
          _lng = (msg['longitude'] as num?)?.toDouble();
          _accuracy = (msg['accuracy'] as num?)?.toDouble();
          _lastUpdate = DateTime.tryParse(msg['timestamp'] as String? ?? '') ?? DateTime.now();
          _breadcrumbCount++;
        });
        break;
      case 'STREAM_TERMINATE':
        setState(() {
          _status = 'ended';
          _live = false;
        });
        _pollTimer?.cancel();
        break;
      case 'ERROR':
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
    if (crumbs is List) _breadcrumbCount = crumbs.length;
    final loc = data['currentLocation'];
    if (loc is Map<String, dynamic>) {
      _lat = (loc['latitude'] as num?)?.toDouble();
      _lng = (loc['longitude'] as num?)?.toDouble();
      _accuracy = (loc['accuracy'] as num?)?.toDouble();
    }
    _lastUpdate = DateTime.now();
    if (_status == 'expired' || _status == 'ended') {
      _pollTimer?.cancel();
      _live = false;
    }
  }

  void _stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ws?.close();
    _ws = null;
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
