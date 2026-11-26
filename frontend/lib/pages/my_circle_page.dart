import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import '../theme/app_colors.dart';

/// M3: My Circle — account-to-account trusted circle.
///
/// Shows the user's public Safe ID (the ONLY address anyone needs to send
/// them a connection request — never an email or phone), incoming requests
/// to accept/decline, and active connections with scoped live views.
/// Every action surfaces the honest server error when it fails.
class MyCirclePage extends StatefulWidget {
  const MyCirclePage({super.key});

  @override
  State<MyCirclePage> createState() => _MyCirclePageState();
}

class _MyCirclePageState extends State<MyCirclePage> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];
  String? _ownSafeId;

  @override
  void initState() {
    super.initState();
    _loadCircle();
  }

  Future<void> _loadCircle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Own Safe ID for the share card (tolerant — may be null on stale profile)
    try {
      final me = await _authService.getProfile();
      _ownSafeId = me?.safeId;
    } catch (_) {
      // Profile read failure must not block circle listing
    }

    final res = await _authService.fetchMyConnections();
    if (!mounted) return;
    if (res['ok'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? {};
      setState(() {
        _incoming = _asList(data['incoming']);
        _outgoing = _asList(data['outgoing']);
        _isLoading = false;
      });
      _publishBeacons(_incoming);
    } else {
      setState(() {
        _errorMessage = res['message']?.toString() ?? 'Could not load your circle.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  String _counterpartName(Map<String, dynamic> conn) {
    final counterpart = conn['counterpart'];
    if (counterpart is Map<String, dynamic> && (counterpart['name'] as String? ?? '').isNotEmpty) {
      return counterpart['name'] as String;
    }
    return 'SafeSphere user';
  }

  String _counterpartSafeId(Map<String, dynamic> conn) {
    final counterpart = conn['counterpart'];
    if (counterpart is Map<String, dynamic>) {
      return counterpart['safeId']?.toString() ?? '—';
    }
    return '—';
  }

  Future<void> _respond(Map<String, dynamic> conn, bool accept) async {
    final res = await _authService.respondToConnection(
      connectionId: conn['id'].toString(),
      accept: accept,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        res['ok'] == true
            ? (accept ? 'Connection accepted — they can now see you per your scopes.' : 'Request declined.')
            : res['message']?.toString() ?? 'Action failed.',
      ),
      backgroundColor: res['ok'] == true ? AppColors.teal : Colors.redAccent,
    ));
    _loadCircle();
  }

  Future<void> _revoke(Map<String, dynamic> conn, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Revoke connection?'),
        content: Text(
          '$name will immediately lose all access to your scoped data. '
          'They can send a new request later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _authService.revokeConnection(conn['id'].toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['ok'] == true ? 'Connection revoked — access removed immediately.' : res['message']?.toString() ?? 'Revoke failed.'),
      backgroundColor: res['ok'] == true ? AppColors.teal : Colors.redAccent,
    ));
    _loadCircle();
  }

  void _showLiveView(Map<String, dynamic> conn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      builder: (_) => _LiveConnectionSheet(connectionId: conn['id'].toString(), name: _counterpartName(conn)),
    );
  }

  Future<void> _showRequestDialog() async {
    final controller = TextEditingController();
    // Dispose the controller only after the modal exit transition finishes —
    // showModalBottomSheet's Future resolves on pop before the route unmounts,
    // so immediate dispose() tears down TextField mid-animation and can
    // leave InheritedElement dependents dirty (`_dependents.isEmpty`).
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      builder: (ctx) => _SendRequestSheet(controller: controller, onSent: _loadCircle),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('My Circle'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadCircle,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Connect by Safe ID',
            onPressed: _showRequestDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Connect'),
        onPressed: _showRequestDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : RefreshIndicator(
              color: AppColors.teal,
              onRefresh: _loadCircle,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SafeIdCard(safeId: _ownSafeId),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    _ErrorCard(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  _sectionHeader('Requests for you', _incoming.where((c) => c['status'] == 'pending').length),
                  ..._incoming.where((c) => c['status'] == 'pending').map(_pendingRequestTile),
                  if (_incoming.where((c) => c['status'] == 'pending').isEmpty)
                    const _EmptyHint('No pending requests. Share your Safe ID with people you trust.'),
                  _sectionHeader('People who can see you', _incoming.where((c) => c['status'] == 'active').length),
                  ..._incoming.where((c) => c['status'] == 'active').map(_watchingMeTile),
                  if (_incoming.where((c) => c['status'] == 'active').isEmpty)
                    const _EmptyHint('Nobody is watching you yet.'),
                  _sectionHeader('People you watch', _outgoing.where((c) => c['status'] == 'active').length),
                  ..._outgoing.where((c) => c['status'] == 'active').map(_watchingTile),
                  ..._outgoing.where((c) => c['status'] == 'pending').map(_pendingSentTile),
                  if (_outgoing.isEmpty)
                    const _EmptyHint('Connect to someone\'s Safe ID to watch over them.'),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: const TextStyle(color: AppColors.teal, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Incoming pending request — owner decides.
  Widget _pendingRequestTile(Map<String, dynamic> conn) {
    final scopes = (conn['scopes'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.pending_actions, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${_counterpartName(conn)} wants to see you',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Safe ID ${_counterpartSafeId(conn)} • requests: ${scopes.join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text('Mode: ${conn['mode'] ?? 'sos_only'}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _respond(conn, false),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _respond(conn, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: Colors.black),
                child: const Text('Accept'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Foreground beacon: for every 'always'-mode connection where someone can
  /// see me, publish the last known position so their live view isn't empty.
  /// Honest scope: fires when this page loads — a true background beacon
  /// needs a foreground service (TODO(REAL_HARDWARE)).
  Future<void> _publishBeacons(List<Map<String, dynamic>> incoming) async {
    final always = incoming.where(
        (c) => c['status'] == 'active' && c['mode'] == 'always');
    if (always.isEmpty) return;
    double? lat;
    double? lng;
    double? acc;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        acc = pos.accuracy;
      }
    } catch (_) {}
    if (lat == null || lng == null) {
      final loc = LocationService.instance;
      if (loc.hasLiveGps || loc.isManualOverride) {
        lat = loc.currentLat;
        lng = loc.currentLng;
      }
    }
    if (lat == null || lng == null) return;
    for (final c in always) {
      final id = c['id']?.toString();
      if (id == null || id.isEmpty) continue;
      try {
        await _authService.pingConnectionLocation(
          connectionId: id,
          latitude: lat,
          longitude: lng,
          accuracy: acc,
        );
      } catch (_) {
        // Beacon failure is non-fatal — the grantee sees last-known staleness.
      }
    }
  }

  /// Renders the latest "check on them" ping for the owner view, if any.
  String _checkInLine(Map<String, dynamic> conn) {
    final ci = conn['lastCheckIn'];
    if (ci is! Map) return '';
    final msg = ci['message']?.toString() ?? '';
    final name = ci['fromName']?.toString() ?? 'They';
    return '\n$name checked on you: "$msg"';
  }

  /// Active incoming — someone can see me. Show scopes + revoke.
  Widget _watchingMeTile(Map<String, dynamic> conn) {
    final scopes = (conn['scopes'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.visibility, color: AppColors.teal),
        title: Text(_counterpartName(conn), style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          'Can see: ${scopes.isEmpty ? 'nothing' : scopes.join(', ')} • mode ${conn['mode'] ?? 'sos_only'}'
          '${_checkInLine(conn)}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.link_off, color: Colors.redAccent),
          tooltip: 'Revoke access',
          onPressed: () => _revoke(conn, _counterpartName(conn)),
        ),
      ),
    );
  }

  /// Active outgoing — I watch someone. Live view + check-in + revoke.
  Widget _watchingTile(Map<String, dynamic> conn) {
    final scopes = (conn['scopes'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.travel_explore, color: AppColors.teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_counterpartName(conn),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
              tooltip: 'Stop watching',
              onPressed: () => _revoke(conn, _counterpartName(conn)),
            ),
          ]),
          Text('Scopes: ${scopes.join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            if (scopes.contains('location'))
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.location_on_outlined, size: 18),
                  label: const Text('Live'),
                  onPressed: () => _showLiveView(conn),
                ),
              ),
            if (scopes.contains('location')) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Check in'),
                onPressed: () => _checkIn(conn),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _pendingSentTile(Map<String, dynamic> conn) {
    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.hourglass_top, color: Colors.amberAccent),
        title: Text(_counterpartName(conn), style: const TextStyle(color: Colors.white)),
        subtitle: const Text('Waiting for them to accept',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: TextButton(
          onPressed: () => _revoke(conn, _counterpartName(conn)),
          child: const Text('Withdraw', style: TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

  Future<void> _checkIn(Map<String, dynamic> conn) async {
    final res = await _authService.checkInOnConnection(
      connectionId: conn['id'].toString(),
      message: 'Checking on you — are you okay?',
    );
    if (!mounted) return;
    final rateLimited = res['code'] == 'CHECKIN_RATE_LIMITED';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        res['ok'] == true
            ? 'Check-in sent. They\'ll see you asked about them.'
            : rateLimited
                ? 'You already checked in recently — wait a few minutes.'
                : res['message']?.toString() ?? 'Check-in failed.',
      ),
      backgroundColor: res['ok'] == true ? AppColors.teal : Colors.amber.shade800,
    ));
  }
}

// ---------------------------------------------------------------------------
// Own Safe ID share card
// ---------------------------------------------------------------------------
class _SafeIdCard extends StatelessWidget {
  final String? safeId;
  const _SafeIdCard({this.safeId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal.withOpacity(0.18), const Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.teal.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('YOUR SAFESPHERE ID',
            style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        Row(children: [
          SelectableText(
            safeId ?? 'unavailable — sign in and refresh',
            style: TextStyle(
              color: safeId != null ? Colors.white : Colors.white38,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
            ),
          ),
          const Spacer(),
          if (safeId != null)
            IconButton(
              icon: const Icon(Icons.copy, color: AppColors.teal),
              tooltip: 'Copy Safe ID',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: safeId!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Safe ID copied — share it only with people you trust.')),
                  );
                }
              },
            ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Anyone with this ID can REQUEST to see you — you approve every request, '
          'pick what they see, and can revoke instantly. It never reveals your '
          'email or phone.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Send request sheet
// ---------------------------------------------------------------------------
class _SendRequestSheet extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSent;
  const _SendRequestSheet({required this.controller, required this.onSent});

  @override
  State<_SendRequestSheet> createState() => _SendRequestSheetState();
}

class _SendRequestSheetState extends State<_SendRequestSheet> {
  final AuthService _authService = AuthService();
  bool _location = true;
  bool _sosStatus = true;
  bool _nearbyAlerts = false;
  bool _alwaysMode = false; // false → sos_only (safer default)
  bool _sending = false;
  String? _resultMessage;
  bool _resultOk = false;

  Future<void> _send() async {
    final safeId = widget.controller.text.trim().toUpperCase();
    if (safeId.isEmpty) {
      setState(() => _resultMessage = 'Enter their Safe ID (looks like SF-7X4K-2Q).');
      return;
    }
    final scopes = [
      if (_location) 'location',
      if (_sosStatus) 'sos_status',
      if (_nearbyAlerts) 'nearby_alerts',
    ];
    if (scopes.isEmpty) {
      setState(() => _resultMessage = 'Pick at least one thing to see.');
      return;
    }
    setState(() {
      _sending = true;
      _resultMessage = null;
    });
    final res = await _authService.sendConnectionRequest(
      ownerSafeId: safeId,
      scopes: scopes,
      mode: _alwaysMode ? 'always' : 'sos_only',
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _resultOk = res['ok'] == true;
      _resultMessage = res['ok'] == true
          ? 'Request sent — they\'ll approve or decline.'
          : res['message']?.toString() ?? 'Request failed.';
    });
    if (res['ok'] == true) {
      widget.onSent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Connect to someone',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Ask their Safe ID — never their email or phone.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controller,
          style: const TextStyle(color: Colors.white, letterSpacing: 2),
          decoration: InputDecoration(
            hintText: 'SF-XXXX-XX',
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        const SizedBox(height: 10),
        const Text('What you\'re asking to see:', style: TextStyle(color: Colors.white70, fontSize: 12)),
        CheckboxListTile(
          value: _location,
          onChanged: (v) => setState(() => _location = v ?? false),
          activeColor: AppColors.teal,
          title: const Text('Live location (beacons)', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Where they are — only while they beacon', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        CheckboxListTile(
          value: _sosStatus,
          onChanged: (v) => setState(() => _sosStatus = v ?? false),
          activeColor: AppColors.teal,
          title: const Text('SOS / trip status', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Whether their SOS or live trip is active', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        CheckboxListTile(
          value: _nearbyAlerts,
          onChanged: (v) => setState(() => _nearbyAlerts = v ?? false),
          activeColor: AppColors.teal,
          title: const Text('Their SOS alerts', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Their distress alerts with location', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        SwitchListTile(
          value: _alwaysMode,
          onChanged: (v) => setState(() => _alwaysMode = v),
          activeColor: AppColors.amber,
          title: const Text('Always-on location', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Off (recommended): location only flows during an active SOS or shared trip.',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        if (_resultMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_resultMessage!,
                style: TextStyle(color: _resultOk ? AppColors.teal : Colors.redAccent, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _sending ? null : _send,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: Colors.black),
            child: _sending
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send request'),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Live connection sheet — polls /live + /status every 5s while open
// ---------------------------------------------------------------------------
class _LiveConnectionSheet extends StatefulWidget {
  final String connectionId;
  final String name;
  const _LiveConnectionSheet({required this.connectionId, required this.name});

  @override
  State<_LiveConnectionSheet> createState() => _LiveConnectionSheetState();
}

class _LiveConnectionSheetState extends State<_LiveConnectionSheet> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _live;
  Map<String, dynamic>? _status;
  String? _errorCode;
  bool _polling = true;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  Future<void> _poll() async {
    while (_polling && mounted) {
      final liveRes = await _authService.fetchConnectionLive(widget.connectionId);
      final statusRes = await _authService.fetchConnectionStatus(widget.connectionId);
      if (!mounted) return;
      setState(() {
        _live = liveRes['ok'] == true ? (liveRes['data'] as Map<String, dynamic>?) : null;
        _status = statusRes['ok'] == true ? (statusRes['data'] as Map<String, dynamic>?) : null;
        if (liveRes['ok'] != true) {
          _errorCode = liveRes['code']?.toString();
        } else {
          _errorCode = null;
        }
      });
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  String _scopeDeniedMessage(String? code) {
    switch (code) {
      case 'CONNECTION_REVOKED':
        return 'This connection was revoked — access removed immediately.';
      case 'SCOPE_NOT_GRANTED':
        return 'They narrowed what you can see — live location is no longer included.';
      case 'SOS_ONLY_NO_ACTIVE_WINDOW':
        return 'sos_only mode — their location flows only during an active SOS or shared trip.';
      case 'CONNECTION_NOT_FOUND':
        return 'Connection no longer exists.';
      default:
        return 'Waiting for signal…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _live != null && _live!['hasSignal'] == true
        ? _live!['location'] as Map<String, dynamic>?
        : null;
    final sosActive = _status != null && _status!['sosActive'] == true;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.satellite_alt, color: AppColors.teal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Live — ${widget.name}',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
        ]),
        if (_errorCode != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
            ),
            child: Text(_scopeDeniedMessage(_errorCode),
                style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
          ),
        ] else if (location != null) ...[
          const SizedBox(height: 10),
          Text('Lat ${location['latitude']}, Lng ${location['longitude']}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          Text('Accuracy ±${location['accuracy'] ?? '?'} m • updated ${location['timestamp'] ?? ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Open in maps'),
            onPressed: () async {
              final uri = Uri.parse('https://www.google.com/maps?q=${location['latitude']},${location['longitude']}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ] else ...[
          const SizedBox(height: 10),
          const Text('No beacon yet — they haven\'t shared a location on this connection.',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
        const SizedBox(height: 10),
        if (_status != null) ...[
          Row(children: [
            Icon(
              sosActive ? Icons.emergency : Icons.check_circle_outline,
              color: sosActive ? Colors.redAccent : AppColors.teal,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              sosActive
                  ? 'SOS ACTIVE${(_status!['sosAlert']?['escalationLevel'] ?? 0) > 0 ? ' — escalated ×${_status!['sosAlert']['escalationLevel']}' : ''}'
                  : 'No active SOS • trip: ${_status!['trackingActive'] == true ? 'running' : 'none'}',
              style: TextStyle(
                color: sosActive ? Colors.redAccent : Colors.white70,
                fontSize: 13,
                fontWeight: sosActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 6),
        const Text('Refreshes every 5 seconds while open.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12)),
    );
  }
}
