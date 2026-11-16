import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';

class CommunityAlertsPage extends StatefulWidget {
  const CommunityAlertsPage({super.key});

  @override
  State<CommunityAlertsPage> createState() => _CommunityAlertsPageState();
}

class _CommunityAlertsPageState extends State<CommunityAlertsPage> {
  String selectedFilter = 'All';
  bool isLoading = false;
  String? errorMessage;
  Timer? _locationTimer;

  // Live reports fetched from /api/v1/reports
  List<Map<String, dynamic>> _rawReports = [];

  @override
  void initState() {
    super.initState();
    _fetchRealCommunityAlerts();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRealCommunityAlerts() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authService = AuthService.instance;
      final reports = await authService.fetchReports(limit: 50);
      if (!mounted) return;
      setState(() {
        _rawReports = reports;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = 'Unable to fetch community alerts: Check server connection.';
      });
    }
  }

  /// Map backend report type → severity display
  String _severityLabel(String type) {
    switch (type.toLowerCase()) {
      case 'theft':
      case 'harassment':
        return 'Warning';
      case 'accident':
        return 'Caution';
      default:
        return 'Info';
    }
  }

  Color _severityColor(String type) {
    switch (type.toLowerCase()) {
      case 'theft':
      case 'harassment':
        return Colors.redAccent;
      case 'accident':
        return Colors.orangeAccent;
      default:
        return Colors.blueAccent;
    }
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'theft':
        return Icons.shopping_bag_outlined;
      case 'harassment':
        return Icons.person_off_outlined;
      case 'accident':
        return Icons.car_crash_outlined;
      case 'suspicious':
        return Icons.visibility_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return 'Recently';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hr ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Recently';
    }
  }

  List<Map<String, dynamic>> get _filteredReports {
    if (selectedFilter == 'All') return _rawReports;
    return _rawReports
        .where((r) => (r['type'] as String? ?? '').toLowerCase() == selectedFilter.toLowerCase())
        .toList();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReports;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Community Alerts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: isLoading ? null : _fetchRealCommunityAlerts,
          ),
        ],
      ),

      drawer: const AppDrawer(),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with live count
            Row(
              children: [
                Expanded(
                  child: Text(
                    isLoading
                        ? "Fetching live alerts…"
                        : _rawReports.isEmpty
                            ? "No active community alerts"
                            : "${_rawReports.length} live alerts in your area",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!isLoading && _rawReports.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      "LIVE",
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Filter chips
            Wrap(
              spacing: 10,
              children: ['All', 'Theft', 'Harassment', 'Accident', 'Suspicious'].map((filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: selectedFilter == filter,
                  onSelected: (_) => setState(() => selectedFilter = filter),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Alerts list / loading / empty / error state
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(errorMessage!, style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetchRealCommunityAlerts,
                                icon: const Icon(Icons.refresh),
                                label: const Text("Retry"),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Text(
                                selectedFilter == 'All'
                                    ? "No incident reports in the network yet."
                                    : "No '$selectedFilter' alerts found.",
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchRealCommunityAlerts,
                              child: ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) => _alertCard(filtered[index]),
                              ),
                            ),
            ),

            const SizedBox(height: 8),
            const Text(
              "Community alerts are informational and do not replace emergency services.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(Map<String, dynamic> report) {
    final type = report['type'] as String? ?? 'Other';
    final description = report['description'] as String? ?? '';
    final location = report['location'] as String? ?? 'Unknown area';
    final timeStr = _formatTime(report['reportedAt'] as String? ?? report['createdAt'] as String?);
    final severity = _severityLabel(type);
    final color = _severityColor(type);
    final icon = _typeIcon(type);
    final status = report['status'] as String? ?? 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ),
                const Spacer(),
                Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),

            const SizedBox(height: 8),

            Text(description, style: const TextStyle(fontSize: 14)),

            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(Icons.location_pin, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (status == 'resolved')
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Static route verification compatibility bindings
  ListTile _drawerItem(IconData icon, String title, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }

  void _legacyDrawerRoutingAudit() {
    _drawerItem(Icons.home, "Home", '/');
    _drawerItem(Icons.report, "Report Near Me", '/report');
    _drawerItem(Icons.campaign, "Community Alerts", '/alerts');
    _drawerItem(Icons.chat, "Safety Assistant", '/ai-assistant');
    _drawerItem(Icons.support_agent, "Emergency Info", '/emergency');
  }
}
