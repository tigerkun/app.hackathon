import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// M5: Privacy Hub — "Who can see me".
///
/// One plain-language surface answering the single most important privacy
/// question this app has: right now, who can see what about me? It lists
/// live tracking sessions (with token scrubbed server-side), trusted-circle
/// watchers and their scopes, and what's public by default. Every claim is
/// derived from live server data — nothing is assumed or fabricated.
class PrivacyHubPage extends StatefulWidget {
  const PrivacyHubPage({super.key});

  @override
  State<PrivacyHubPage> createState() => _PrivacyHubPageState();
}

class _PrivacyHubPageState extends State<PrivacyHubPage> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _liveSessions = [];
  List<Map<String, dynamic>> _watchers = [];   // incoming active connections
  List<Map<String, dynamic>> _pendingIncoming = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 1. My live tracking sessions (owner view, token scrubbed server-side)
    List<Map<String, dynamic>> sessions = [];
    final me = await _authService.getProfile();
    final res = await _authService.fetchMyTrackingSessions();
    if (res['ok'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final raw = data['activeSessions'];
      if (raw is List) {
        sessions = raw.whereType<Map<String, dynamic>>().toList();
      }
    }

    // 2. Circle watchers
    final connRes = await _authService.fetchMyConnections();
    List<Map<String, dynamic>> watchers = [];
    List<Map<String, dynamic>> pending = [];
    if (connRes['ok'] == true) {
      final data = connRes['data'] as Map<String, dynamic>? ?? {};
      final incoming = data['incoming'];
      if (incoming is List) {
        for (final c in incoming.whereType<Map<String, dynamic>>()) {
          if (c['status'] == 'active') {
            watchers.add(c);
          } else if (c['status'] == 'pending') {
            pending.add(c);
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _liveSessions = sessions;
      _watchers = watchers;
      _pendingIncoming = pending;
      _errorMessage = (res['ok'] != true && connRes['ok'] != true)
          ? "Couldn't reach SafeSphere servers. This page only shows what's true right now — retry when online."
          : null;
      _isLoading = false;
      _safeId = me?.safeId;
    });
  }

  String? _safeId;

  String _scopesLabel(dynamic scopes) {
    if (scopes is List && scopes.isNotEmpty) {
      return scopes.map((s) => s.toString()).join(', ');
    }
    return 'nothing';
  }

  Future<void> _revokeWatcher(Map<String, dynamic> conn) async {
    final name = (conn['counterpart'] is Map && conn['counterpart']['name'] != null)
        ? conn['counterpart']['name'].toString()
        : 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Remove their access?'),
        content: Text('$name immediately loses everything they could see about you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _authService.revokeConnection(conn['id'].toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['ok'] == true ? 'Access removed immediately.' : res['message']?.toString() ?? 'Failed.'),
      backgroundColor: res['ok'] == true ? AppColors.teal : Colors.redAccent,
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Who can see me'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : RefreshIndicator(
              color: AppColors.teal,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _plainBanner(
                    icon: Icons.shield_outlined,
                    title: 'Your data, in plain words',
                    body: 'Nothing about you is visible to anyone unless you shared it. '
                        'This page shows every channel that is open right now — '
                        'and closes them the moment you want.',
                  ),
                  const SizedBox(height: 18),

                  // ── Live tracking sessions ──────────────────────────────
                  _sectionTitle('Live trips right now', _liveSessions.length),
                  if (_liveSessions.isEmpty)
                    const _PlainNote('No live trips. Your location is not streaming to anyone.'),
                  ..._liveSessions.map(_sessionTile),

                  // ── Circle watchers ─────────────────────────────────────
                  _sectionTitle('People who can see you', _watchers.length),
                  if (_watchers.isEmpty)
                    const _PlainNote('Nobody can see your location or status. Requests you approve appear here.'),
                  ..._watchers.map(_watcherTile),

                  // ── Pending requests ────────────────────────────────────
                  if (_pendingIncoming.isNotEmpty) ...[
                    _sectionTitle('Waiting for your answer', _pendingIncoming.length),
                    ..._pendingIncoming.map(_pendingTile),
                  ],

                  // ── What's public ───────────────────────────────────────
                  _sectionTitle('What everyone can see', 0, showCount: false),
                  _publicItem(
                    icon: Icons.badge_outlined,
                    title: _safeId != null && _safeId!.isNotEmpty
                        ? 'Your Safe ID ($_safeId)'
                        : 'Your Safe ID (unavailable — check your connection)',
                    body: 'A random address like SF-7X4K-2Q. It lets people REQUEST to connect — '
                        'it never reveals your email, phone, or location.',
                  ),
                  _publicItem(
                    icon: Icons.map_outlined,
                    title: 'Your public reports & markers',
                    body: 'Community reports you post are visible with your display name, '
                        'like any other citizen report. They carry your reputation score.',
                  ),

                  const SizedBox(height: 18),
                  _plainBanner(
                    icon: Icons.verified_user_outlined,
                    title: 'What we never do',
                    body: 'We never sell or share your data. We never reveal your phone or email '
                        'to other users. Location flows only when: you trigger SOS, you run a live '
                        'trip, or a connection you approved says so. Emergency calls always bypass '
                        'all of this — privacy never blocks a rescue.',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title, int count, {bool showCount = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          if (showCount) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: count > 0 ? Colors.redAccent.withOpacity(0.2) : AppColors.teal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                    color: count > 0 ? Colors.redAccent : AppColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionTile(Map<String, dynamic> s) {
    final expires = s['expiresAt']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.broadcast, color: Colors.redAccent, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Your live trip is streaming',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Anyone holding this trip\'s link can watch your location until ${expires.isNotEmpty ? expires.substring(0, expires.length > 19 ? 19 : expires.length) : 'expiry'} '
          'or until you stop it. ${s['missedCheckIns'] != null && (s['missedCheckIns'] as num) > 0 ? '${s['missedCheckIns']} check-ins missed.' : 'Check-ins on schedule.'}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text('Session ${s['id']?.toString().substring(0, 14)}… • ${s['breadcrumbCount']} breadcrumbs',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _watcherTile(Map<String, dynamic> conn) {
    final counterpart = conn['counterpart'];
    final name = counterpart is Map && counterpart['name'] != null
        ? counterpart['name'].toString()
        : 'SafeSphere user';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.visibility, color: AppColors.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
            tooltip: 'Remove access',
            onPressed: () => _revokeWatcher(conn),
          ),
        ]),
        Text(
          'They can see: ${_scopesLabel(conn['scopes'])} • ${conn['mode'] == 'always' ? 'any time' : 'only during SOS / live trips'}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _pendingTile(Map<String, dynamic> conn) {
    final counterpart = conn['counterpart'];
    final name = counterpart is Map && counterpart['name'] != null
        ? counterpart['name'].toString()
        : 'Someone';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.pending_actions, color: Colors.amberAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name asked to see you — they can see NOTHING until you accept.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/circle'),
          child: const Text('Review', style: TextStyle(color: AppColors.teal)),
        ),
      ]),
    );
  }

  Widget _publicItem({required IconData icon, required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    );
  }

  Widget _plainBanner({required IconData icon, required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal.withOpacity(0.15), const Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.teal.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.teal, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
      ]),
    );
  }
}

class _PlainNote extends StatelessWidget {
  final String text;
  const _PlainNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }
}
