// F5-1: Hardware panic gestures (volume-down long-press ~1.5s via volume_controller and shake-to-SOS
// via sensors_plus) with honest gating, intermediate confirmation, and mandatory 5s countdown dialog.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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

  @override
  void dispose() {
    GestureService.instance.stopListening();
    super.dispose();
  }

  Future<void> _refreshDashboard() async {
    setState(() => _isLoading = true);

    try {
      // 1. Detect user position if permitted
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 4)),
        ).timeout(const Duration(seconds: 4));

        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _locationLabel = "GPS: ${_userLat!.toStringAsFixed(2)}, ${_userLng!.toStringAsFixed(2)}";
      } else {
        _userLat = null;
        _userLng = null;
        _locationLabel = "Unavailable — enable location";
      }
    } catch (_) {
      _userLat = null;
      _userLng = null;
      _locationLabel = "Unavailable — enable location";
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
    if (_isBackendUnavailable) return "Unavailable — connect to backend";
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
    final recentReports = _reports.take(3).toList();

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
          onTap: _refreshDashboard,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 18, color: AppColors.teal),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _locationLabel,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'home_fab_ai',
            backgroundColor: AppColors.purple,
            tooltip: "AI Safety Assistant",
            child: const Icon(Icons.smart_toy, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/ai-assistant');
            },
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: "Trigger emergency SOS",
            child: FloatingActionButton.extended(
              heroTag: 'home_fab_sos',
              backgroundColor: const Color(0xFFDC2626),
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              label: const Text(
                "EMERGENCY SOS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.1,
                ),
              ),
              tooltip: "Immediate Emergency SOS",
              onPressed: () {
                Navigator.pushNamed(context, '/emergency');
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        color: AppColors.teal,
        backgroundColor: const Color(0xFF101A33),
        child: ListView(
          padding: const EdgeInsets.all(16),
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
                  height: MediaQuery.of(context).size.height * 0.40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "EMERGENCY SOS",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Press for immediate help",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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
                    Icon(_isBackendUnavailable ? Icons.cloud_off : Icons.shield, size: 28, color: safetyColor),
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
                                ? "Connect to backend to assess local safety"
                                : "Based on ${_reports.length} verified community report(s)",
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _isBackendUnavailable
                          ? (_lastFetchTime != null
                              ? "Offline"
                              : "Syncing...")
                          : (_lastFetchTime != null
                              ? "Synced ${_formatRelativeTime(_lastFetchTime!.toIso8601String())}"
                              : ""),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_off, color: AppColors.amber, size: 22),
                  title: Text("Activity feed unavailable — connect to backend", style: TextStyle(color: Colors.white70)),
                  subtitle: Text("Connect to backend to view recent activity", style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                                  ? "Unavailable — connect to backend"
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
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isBackendUnavailable ? "—" : "${_reports.length}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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
