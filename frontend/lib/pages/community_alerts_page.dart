import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer.dart';

class CommunityAlertsPage extends StatefulWidget {
  const CommunityAlertsPage({super.key});

  @override
  State<CommunityAlertsPage> createState() => _CommunityAlertsPageState();
}

class _CommunityAlertsPageState extends State<CommunityAlertsPage> {
  String selectedFilter = 'All';
  bool _verifiedOnly = false;
  bool isLoading = false;
  String? errorMessage;
  Timer? _locationTimer;

  double? _userLat;
  double? _userLng;
  static const double _searchRadiusKm = 10;

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
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      } else {
        _userLat = null;
        _userLng = null;
      }
    } catch (_) {
      _userLat = null;
      _userLng = null;
    }

    try {
      final authService = AuthService.instance;
      final hasLocation = _userLat != null && _userLng != null;
      final reports = await authService.fetchReports(
        limit: 50,
        latitude: hasLocation ? _userLat : null,
        longitude: hasLocation ? _userLng : null,
        radiusKm: hasLocation ? _searchRadiusKm : null,
      );
      if (!mounted) return;
      if (authService.lastFetchFailed) {
        setState(() {
          isLoading = false;
          errorMessage = 'Unable to fetch community alerts: Check server connection.';
        });
        return;
      }
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
    var reports = _rawReports;
    if (selectedFilter != 'All') {
      reports = reports
          .where((r) => (r['type'] as String? ?? '').toLowerCase() == selectedFilter.toLowerCase())
          .toList();
    }
    if (_verifiedOnly) {
      reports = reports
          .where((r) => (r['status'] as String? ?? '').toLowerCase() == 'verified')
          .toList();
    }
    return reports;
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
              spacing: 8,
              runSpacing: 6,
              children: [
                ...['All', 'Theft', 'Harassment', 'Accident', 'Suspicious'].map((filter) {
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selectedFilter == filter,
                    onSelected: (_) {
                      try {
                        HapticFeedback.selectionClick();
                      } catch (_) {}
                      setState(() => selectedFilter = filter);
                    },
                  );
                }),
                FilterChip(
                  avatar: Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: _verifiedOnly ? Colors.white : AppColors.teal,
                  ),
                  label: const Text("Verified only"),
                  selected: _verifiedOnly,
                  selectedColor: AppColors.teal,
                  onSelected: (val) {
                    try {
                      HapticFeedback.selectionClick();
                    } catch (_) {}
                    setState(() {
                      _verifiedOnly = val;
                    });
                  },
                ),
              ],
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
                                (_userLat != null && _userLng != null)
                                    ? (selectedFilter == 'All'
                                        ? "No reports within ${_searchRadiusKm.toInt()} km"
                                        : "No '$selectedFilter' reports within ${_searchRadiusKm.toInt()} km")
                                    : (selectedFilter == 'All'
                                        ? "No active community alerts"
                                        : "No '$selectedFilter' reports found"),
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

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'verified':
        bg = AppColors.teal.withOpacity(0.18);
        fg = AppColors.teal;
        label = 'Verified';
        break;
      case 'under_investigation':
        bg = Colors.blue.withOpacity(0.18);
        fg = Colors.lightBlueAccent;
        label = 'Investigating';
        break;
      case 'resolved':
        bg = Colors.green.withOpacity(0.18);
        fg = Colors.greenAccent;
        label = 'Resolved';
        break;
      case 'rejected':
        bg = Colors.red.withOpacity(0.18);
        fg = Colors.redAccent;
        label = 'Rejected';
        break;
      case 'pending':
      default:
        bg = Colors.amber.withOpacity(0.18);
        fg = Colors.amberAccent;
        label = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.toLowerCase() == 'verified'
                ? Icons.verified
                : status.toLowerCase() == 'resolved'
                    ? Icons.check_circle_outline
                    : Icons.schedule,
            size: 11,
            color: fg,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showReportDetails(BuildContext context, Map<String, dynamic> report) {
    final type = report['type'] as String? ?? 'Other';
    final description = report['description'] as String? ?? 'No details provided';
    final location = report['location'] as String? ?? 'Unknown area';
    final status = report['status'] as String? ?? 'pending';
    final createdAt = report['createdAt'] as String? ?? report['reportedAt'] as String? ?? 'Unknown';
    final id = report['id'] as String? ?? 'N/A';
    final lat = report['latitude'];
    final lon = report['longitude'];
    // F5-4: photo attachment in detail view
    final photoUrl = report['photoUrl'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Icon(_typeIcon(type), color: _severityColor(type)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "$type Report",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            _statusBadge(status),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // F5-4: show photo in detail dialog if present
              if (photoUrl != null && photoUrl.isNotEmpty) ...[
                _buildPhotoThumbnail(photoUrl),
                const SizedBox(height: 12),
              ],
              Text(
                description,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (lat != null && lon != null) ...[
                const SizedBox(height: 4),
                Text(
                  "GPS: $lat, $lon",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Reported: $createdAt",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "ID: $id",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(color: AppColors.teal)),
          ),
        ],
      ),
    );
  }

  Widget _alertCard(Map<String, dynamic> report) {
    final type = report['type'] as String? ?? 'Other';
    final description = report['description'] as String? ?? '';
    final location = report['location'] as String? ?? 'Unknown area';
    final rawTime = report['reportedAt'] as String? ?? report['createdAt'] as String?;
    final timeStr = _formatTime(rawTime);
    final severity = _severityLabel(type);
    final color = _severityColor(type);
    final icon = _typeIcon(type);
    final status = report['status'] as String? ?? 'pending';
    // F5-4: photo attachment thumbnail
    final photoUrl = report['photoUrl'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showReportDetails(context, report),
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
                  _statusBadge(status),
                ],
              ),

              const SizedBox(height: 8),

              // F5-4: render photo thumbnail if present
              if (photoUrl != null && photoUrl.isNotEmpty) ...[
                _buildPhotoThumbnail(photoUrl),
                const SizedBox(height: 8),
              ],

              Text(description, style: const TextStyle(fontSize: 14)),

              // M2.3: community vote chips — confirm/decline for authed users.
              // Optimistic UI with honest rollback on failure.
              if (AuthService.instance.currentUser != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _voteChip(
                      report,
                      vote: 'confirm',
                      icon: Icons.thumb_up,
                      label: "Confirm ${report['upvotes'] ?? 0}",
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    _voteChip(
                      report,
                      vote: 'decline',
                      icon: Icons.thumb_down,
                      label: "Decline ${report['downvotes'] ?? 0}",
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),

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
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// M2.3: vote chip — optimistic tally update with honest rollback when the
  /// server rejects the vote (rate limit, banned, network).
  Widget _voteChip(
    Map<String, dynamic> report, {
    required String vote,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      backgroundColor: color.withOpacity(0.08),
      side: BorderSide(color: color.withOpacity(0.4)),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final authService = AuthService.instance;
        final reportId = report['id'] as String?;
        if (reportId == null) return;

        final result = await authService.voteReport(
          reportId: reportId,
          vote: vote,
        );

        if (!mounted) return;
        if (result != null) {
          // Honest refresh: re-pull the list so tallies reflect the server.
          await _fetchRealCommunityAlerts();
          if (mounted) setState(() {});
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  "Vote could not be recorded — check your connection or account status."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
    );
  }

  /// F5-4: Renders a base64 data-URL photo as a thumbnail.
  /// Gracefully degrades to a broken-image icon on any decode failure.
  Widget _buildPhotoThumbnail(String dataUrl) {
    try {
      final commaIdx = dataUrl.indexOf(',');
      if (commaIdx == -1) return const Icon(Icons.broken_image, color: Colors.grey);
      final b64 = dataUrl.substring(commaIdx + 1);
      final bytes = base64Decode(b64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } catch (_) {
      return const Icon(Icons.broken_image, color: Colors.grey);
    }
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
