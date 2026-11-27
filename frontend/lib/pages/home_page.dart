// F5-1: Hardware panic gestures (volume-down long-press ~1.5s via volume_controller and shake-to-SOS
// via sensors_plus) with honest gating, intermediate confirmation, and mandatory 5s countdown dialog.

import 'package:flutter/material.dart';
import '../data/auth_state.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import '../services/gesture_service.dart';
import 'auth/login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;
  String _locationLabel = "Detecting location...";
  double? _userLat;
  double? _userLng;
  List<Map<String, dynamic>> _reports = [];
  DateTime? _lastFetchTime;
  List<Map<String, dynamic>> _queuedSos = [];

  @override
  void initState() {
    super.initState();
    LocationService.instance.addListener(_onLocationServiceChanged);
    _refreshDashboard();
    _loadQueuedSos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GestureService.instance.startListening(
          context,
          onSosConfirmed: () async {
            if (mounted) {
              Navigator.pushNamed(context, '/emergency');
            }
          },
        );
      }
    });
  }

  void _onLocationServiceChanged() {
    if (!mounted) return;
    final loc = LocationService.instance;
    final changed = _userLat != loc.currentLat ||
        _userLng != loc.currentLng ||
        _locationLabel != loc.locationLabel;
    if (changed) {
      setState(() {
        _userLat = loc.currentLat;
        _userLng = loc.currentLng;
        _locationLabel = loc.locationLabel;
      });
      _refreshDashboard();
    }
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onLocationServiceChanged);
    GestureService.instance.stopListening(context);
    super.dispose();
  }

  Future<void> _refreshDashboard() async {
    setState(() => _isLoading = true);

    try {
      // 1. Detect or apply user position from LocationService
      final loc = LocationService.instance;
      if (loc.isManualOverride) {
        _userLat = loc.currentLat;
        _userLng = loc.currentLng;
        _locationLabel = loc.locationLabel;
      } else {
        final success = await loc.detectLiveGps();
        if (success) {
          _userLat = loc.currentLat;
          _userLng = loc.currentLng;
          _locationLabel = loc.locationLabel;
        } else {
          _userLat = loc.currentLat;
          _userLng = loc.currentLng;
          _locationLabel = loc.locationLabel;
        }
      }
    } catch (_) {
      _userLat = LocationService.instance.currentLat;
      _userLng = LocationService.instance.currentLng;
      _locationLabel = LocationService.instance.locationLabel;
    }

    try {
      // 2. Fetch live community reports from real backend
      final auth = AuthService.instance;
      final hasLocation = _userLat != null && _userLng != null;
      final fetched = await auth.fetchReports(
        limit: 10,
        latitude: hasLocation ? _userLat : null,
        longitude: hasLocation ? _userLng : null,
        radiusKm: hasLocation ? 10 : null,
      );
      if (mounted) {
        setState(() {
          if (!auth.lastFetchFailed) {
            _reports = fetched;
            _lastFetchTime = DateTime.now();
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    // M1.7: refresh the queued-SOS banner state
    await _loadQueuedSos();
  }

  bool get _isBackendUnavailable => AuthService.instance.lastFetchFailed;

  /// M1.7: honest queued-SOS banner state — pending offline SOS alerts show
  /// "will send automatically when signal returns" with their queue time.
  Future<void> _loadQueuedSos() async {
    try {
      final queued = await AuthService.instance.getQueuedSosAlerts();
      if (mounted) setState(() => _queuedSos = queued);
    } catch (_) {
      // Queue read is best-effort; the banner simply won't show.
    }
  }

  String _queuedAtLabel() {
    final stamps = _queuedSos
        .map((e) => e['_queuedAt'])
        .whereType<String>()
        .toList();
    if (stamps.isEmpty) return 'unknown';
    try {
      final dt = DateTime.parse(stamps.first).toLocal();
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return 'unknown';
    }
  }

  String _calculateSafetyLevel() {
    if (_isBackendUnavailable) return "Offline Safety Mode";
    if (_lastFetchTime == null && _isLoading) return "Assessing local safety...";
    final count = _reports.length;
    if (count == 0) return "Safety Level: High";
    if (count <= 3) return "Safety Level: Moderate";
    return "Safety Level: High Caution";
  }

  Color _getSafetyLevelColor() {
    if (_isBackendUnavailable) return AppColors.amber;
    if (_lastFetchTime == null && _isLoading) return AppColors.textSecondary;
    final count = _reports.length;
    if (count == 0) return AppColors.teal;
    if (count <= 3) return AppColors.amber;
    return AppColors.red;
  }

  String _formatRelativeTime(dynamic isoString) {
    if (isoString == null) return "recently";
    try {
      final dt = DateTime.parse(isoString.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return "just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
      if (diff.inHours < 24) return "${diff.inHours}h ago";
      return "${diff.inDays}d ago";
    } catch (_) {
      return "recently";
    }
  }

  IconData _iconForReportType(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('theft')) return Icons.report_problem;
    if (t.contains('harass')) return Icons.visibility;
    if (t.contains('accident')) return Icons.car_crash;
    if (t.contains('light') || t.contains('dark')) return Icons.lightbulb_outline;
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final safetyLevel = _calculateSafetyLevel();
    final safetyColor = _getSafetyLevelColor();
    // "Recent Local Activity" must show current concerns only: resolved or
    // expired reports and week-old items are not recent activity.
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final recentReports = _reports.where((r) {
      final st = (r['status'] as String? ?? 'pending').toLowerCase();
      if (st == 'resolved' || st == 'expired' || st == 'closed') return false;
      final raw = r['createdAt'] as String? ?? r['reportedAt'] as String? ?? '';
      final dt = DateTime.tryParse(raw);
      if (dt != null && dt.isBefore(cutoff)) return false;
      return true;
    }).take(3).toList();

    return ListenableBuilder(
      listenable: AuthState(),
      builder: (context, _) {
        final discreet = AuthState().isDiscreetMode;
        return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: InkWell(
          onTap: () {
            LocationService.showLocationPickerSheet(
              context,
              onLocationChanged: () {
                _refreshDashboard();
              },
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LocationService.instance.isManualOverride
                      ? Icons.edit_location_alt
                      : (_userLat != null ? Icons.location_on : Icons.location_off_outlined),
                  size: 15,
                  color: LocationService.instance.isManualOverride
                      ? AppColors.blue
                      : (_userLat != null ? AppColors.teal : AppColors.amber),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _locationLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: AppColors.teal),
            tooltip: "Account & PIN Security",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: "Trigger emergency SOS",
        child: FloatingActionButton.extended(
          heroTag: 'home_fab_sos',
          backgroundColor: discreet ? const Color(0xFF334155) : const Color(0xFFDC2626),
          icon: Icon(
            discreet ? Icons.shield_outlined : Icons.warning_amber_rounded,
            color: Colors.white,
            size: 22,
          ),
          label: Text(
            discreet ? "SAFETY OPTIONS" : "EMERGENCY SOS",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1.1,
            ),
          ),
          tooltip: "Immediate Emergency SOS",
          onPressed: () {
            Navigator.pushNamed(context, '/emergency');
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        color: AppColors.teal,
        backgroundColor: const Color(0xFF101A33),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            /// 🆘 SOS-FIRST HERO (M1.1): the dominant first-paint element.
            /// Minimum 40% of viewport, high-contrast red, one-handed reach.
            /// Everything else on this page is secondary.
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/emergency'),
              child: Semantics(
                button: true,
                label: "Trigger emergency SOS now",
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  width: double.infinity,
                  height: (MediaQuery.of(context).size.height * 0.32).clamp(200.0, 260.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: discreet
                          ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
                          : const [Color(0xFFE11D48), Color(0xFFDC2626), Color(0xFF991B1B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: discreet ? Colors.white24 : Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: discreet
                            ? Colors.black.withValues(alpha: 0.25)
                            : const Color(0xFFDC2626).withValues(alpha: 0.38),
                        blurRadius: discreet ? 12 : 22,
                        offset: const Offset(0, 6),
                        spreadRadius: discreet ? 0 : 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: discreet ? 0.08 : 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: discreet ? 0.2 : 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          discreet ? Icons.shield_outlined : Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        discreet ? "SAFETY CHECK" : "EMERGENCY SOS",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        discreet
                            ? "Discreet mode active — tap for options"
                            : "Press for immediate help",
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              discreet ? "OPEN OPTIONS" : "GET HELP NOW",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// ⏳ QUEUED-SOS HONEST BANNER (M1.7): pending offline alerts
            /// tell the truth about their state and auto-send on signal.
            if (_queuedSos.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.amber, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_send,
                        color: AppColors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "${_queuedSos.length} SOS alert(s) queued — will send automatically when signal returns • Queued at ${_queuedAtLabel()}",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            /// 1️⃣ LOCAL SAFETY STATUS (condensed strip — secondary to SOS)
            GlassContainer(
              borderColor: safetyColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(_isBackendUnavailable ? Icons.shield_outlined : Icons.shield, size: 28, color: safetyColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            safetyLevel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isBackendUnavailable
                                ? "Emergency dialer (112) active • Tap to sync telemetry"
                                : "Based on ${_reports.length} verified community report(s)",
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_isBackendUnavailable)
                      InkWell(
                        onTap: _refreshDashboard,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, size: 12, color: AppColors.amber),
                              SizedBox(width: 4),
                              Text("Retry", style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    else
                      Text(
                        _lastFetchTime != null
                            ? "Synced ${_formatRelativeTime(_lastFetchTime!.toIso8601String())}"
                            : "",
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// 2️⃣ PRIMARY ACTIONS
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.report,
                    title: "Report Near Me",
                    subtitle: "Submit a safety concern",
                    color: AppColors.amber,
                    onTap: () => Navigator.pushNamed(context, '/report'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.map,
                    title: "Safety Map",
                    subtitle: "View nearby alerts",
                    color: AppColors.blue,
                    onTap: () => Navigator.pushNamed(context, '/safety-map'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            /// 🤖 AI SAFETY RECOMMENDATIONS
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/ai-assistant'),
              child: GlassContainer(
                borderColor: AppColors.purple,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.smart_toy,
                          color: AppColors.purple,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "AI Safety Assistant",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Interactive guidance and emergency escalation",
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white38),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// 3️⃣ RECENT LOCAL ACTIVITY
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Recent Local Activity",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (_isBackendUnavailable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wifi_off_outlined, color: AppColors.amber, size: 22),
                  title: const Text("Offline Safety Guides Active", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text("Emergency SOS works offline via SMS and cached contacts", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: TextButton(
                    onPressed: _refreshDashboard,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: const Text("Retry", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              )
            else if (recentReports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline, color: AppColors.teal, size: 22),
                  title: Text("No reports within 10 km", style: TextStyle(color: Colors.white70)),
                  subtitle: Text("Area is calm • Stay vigilant", style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              )
            else
              for (final report in recentReports)
                _ActivityItem(
                  icon: _iconForReportType(report['type']?.toString()),
                  text: "${report['type'] ?? 'Alert'}: ${report['description'] ?? report['location'] ?? ''}",
                  time: _formatRelativeTime(report['createdAt']),
                ),

            const SizedBox(height: 16),

            /// 5️⃣ COMMUNITY ALERTS PREVIEW
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/alerts'),
              child: GlassContainer(
                borderColor: AppColors.red,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.notifications_active, color: AppColors.red),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Community Alerts",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isBackendUnavailable
                                  ? "Offline — tap to view safety map & offline refuges"
                                  : "${_reports.length} verified alert(s) in active area",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isBackendUnavailable ? AppColors.amber.withValues(alpha: 0.2) : AppColors.red,
                          borderRadius: BorderRadius.circular(20),
                          border: _isBackendUnavailable ? Border.all(color: AppColors.amber.withValues(alpha: 0.4)) : null,
                        ),
                        child: Text(
                          _isBackendUnavailable ? "Offline" : "${_reports.length}",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isBackendUnavailable ? AppColors.amber : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// 6️⃣ SAFETY TIP
            GlassContainer(
              borderColor: AppColors.teal,
              child: const ListTile(
                leading: Icon(Icons.info, color: AppColors.teal),
                title: Text(
                  "Prefer well-lit routes while traveling at night",
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// 7️⃣ EMERGENCY STRIP
            const Center(
              child: Text(
                "For immediate danger, contact emergency services (112).",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

/// SMALL HELPERS (NO LOGIC)
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderColor: color,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        time,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}
