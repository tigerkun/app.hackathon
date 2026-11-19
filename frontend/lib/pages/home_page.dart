import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import 'auth/login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;
  String _locationLabel = "Detecting location...";
  double _userLat = SafeSphereMapConfig.defaultLatitude;
  double _userLng = SafeSphereMapConfig.defaultLongitude;
  List<Map<String, dynamic>> _reports = [];
  DateTime? _lastFetchTime;

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
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
        _locationLabel = "GPS: ${_userLat.toStringAsFixed(2)}, ${_userLng.toStringAsFixed(2)}";
      } else {
        _locationLabel = "Unavailable — enable location";
      }
    } catch (_) {
      _locationLabel = "Unavailable — enable location";
    }

    try {
      // 2. Fetch live community reports from real backend
      final auth = AuthService.instance;
      final fetched = await auth.fetchReports(
        limit: 10,
        latitude: _userLat,
        longitude: _userLng,
        radiusKm: 10,
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
  }

  bool get _isBackendUnavailable => AuthService.instance.lastFetchFailed;

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
        title: Row(
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.smart_toy),
        onPressed: () {
          Navigator.pushNamed(context, '/ai-assistant');
        },
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        color: AppColors.teal,
        backgroundColor: const Color(0xFF101A33),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            /// 1️⃣ INTENT HEADLINE
            const Text(
              "How can we help you stay safe today?",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Real-time safety insights from your community",
              style: TextStyle(color: Colors.white60),
            ),

            const SizedBox(height: 20),

            /// 2️⃣ LOCAL SAFETY STATUS (ANCHOR CARD)
            GlassContainer(
              borderColor: safetyColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_isBackendUnavailable ? Icons.cloud_off : Icons.shield, size: 40, color: safetyColor),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            safetyLevel,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isBackendUnavailable
                                ? "Connect to backend to assess local safety"
                                : (_lastFetchTime == null && _isLoading)
                                    ? "Connecting to live safety telemetry..."
                                    : "Based on ${_reports.length} verified community report(s)",
                            style: const TextStyle(color: Colors.white60),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isBackendUnavailable
                                ? (_lastFetchTime != null
                                    ? "Last synced: ${_formatRelativeTime(_lastFetchTime!.toIso8601String())} (Offline)"
                                    : "Sync failed — pull down to retry")
                                : (_lastFetchTime != null
                                    ? "Last synced: ${_formatRelativeTime(_lastFetchTime!.toIso8601String())}"
                                    : "Syncing live telemetry..."),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// 3️⃣ PRIMARY ACTIONS
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
            const SizedBox(height: 20),

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

            /// 4️⃣ RECENT LOCAL ACTIVITY
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
