import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/map_config.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_widgets.dart';
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
  bool _allAreas = false;
  static const double _searchRadiusKm = 15;

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

    final loc = LocationService.instance;
    if (!_allAreas) {
      if (!loc.isManualOverride && !loc.hasLiveGps) {
        await loc.detectLiveGps();
      }
      _userLat = loc.currentLat;
      _userLng = loc.currentLng;
    } else {
      _userLat = null;
      _userLng = null;
    }

    try {
      final authService = AuthService.instance;
      final hasLocation = !_allAreas && _userLat != null && _userLng != null;
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

  static const Set<String> _crimeTypes = {'theft', 'harassment', 'assault', 'suspicious'};
  static const Set<String> _infraTypes = {'dark area', 'road hazard', 'flooding', 'transit issue', 'accident', 'other'};

  /// Map backend report type → severity display
  String _severityLabel(String type) {
    switch (type.toLowerCase()) {
      case 'theft':
      case 'harassment':
      case 'assault':
        return 'Threat';
      case 'dark area':
      case 'road hazard':
      case 'flooding':
      case 'transit issue':
        return 'Infra';
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
      case 'assault':
        return Colors.redAccent;
      case 'dark area':
        return Colors.amberAccent;
      case 'road hazard':
      case 'flooding':
      case 'transit issue':
        return AppColors.purple;
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
      case 'assault':
        return Icons.gpp_bad_outlined;
      case 'accident':
        return Icons.car_crash_outlined;
      case 'suspicious':
        return Icons.visibility_outlined;
      case 'dark area':
        return Icons.lightbulb_outline;
      case 'road hazard':
        return Icons.construction_outlined;
      case 'flooding':
        return Icons.water_drop_outlined;
      case 'transit issue':
        return Icons.directions_bus_outlined;
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
    if (selectedFilter == 'Crimes') {
      reports = reports
          .where((r) => _crimeTypes.contains((r['type'] as String? ?? '').toLowerCase()))
          .toList();
    } else if (selectedFilter == 'Infrastructure') {
      reports = reports
          .where((r) => _infraTypes.contains((r['type'] as String? ?? '').toLowerCase()))
          .toList();
    } else if (selectedFilter != 'All') {
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

  /// Reports that still represent an ongoing concern. Resolved/expired
  /// items stay visible in the feed (badged) but must not inflate the
  /// "live alerts" count.
  List<Map<String, dynamic>> get _liveReports => _rawReports
      .where((r) {
        final st = (r['status'] as String? ?? 'pending').toLowerCase();
        return st != 'resolved' && st != 'expired' && st != 'closed';
      })
      .toList();

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
                        : _liveReports.isEmpty
                            ? "No active community alerts"
                            : "${_liveReports.length} live alerts in your area",
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

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      LocationService.showLocationPickerSheet(
                        context,
                        onLocationChanged: () {
                          setState(() => _allAreas = false);
                          _fetchRealCommunityAlerts();
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _allAreas ? Icons.public : Icons.location_on,
                            size: 14,
                            color: _allAreas ? AppColors.blue : AppColors.teal,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _allAreas
                                  ? "Showing all areas"
                                  : "Near ${LocationService.instance.locationLabel} (15 km)",
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
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text("All Areas", style: TextStyle(fontSize: 12)),
                  selected: _allAreas,
                  onSelected: (val) {
                    setState(() => _allAreas = val);
                    _fetchRealCommunityAlerts();
                  },
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Filter chips (grouped Reddit-like topic filters)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...[
                    'All',
                    'Crimes',
                    'Infrastructure',
                    'Theft',
                    'Harassment',
                    'Assault',
                    'Suspicious',
                    'Dark Area',
                    'Road Hazard',
                    'Flooding',
                    'Transit Issue',
                    'Accident',
                  ].map((filter) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(filter, style: const TextStyle(fontSize: 12)),
                        selected: selectedFilter == filter,
                        onSelected: (_) {
                          try {
                            HapticFeedback.selectionClick();
                          } catch (_) {}
                          setState(() => selectedFilter = filter);
                        },
                      ),
                    );
                  }),
                  FilterChip(
                    avatar: Icon(
                      Icons.verified_outlined,
                      size: 16,
                      color: _verifiedOnly ? Colors.white : AppColors.teal,
                    ),
                    label: const Text("Verified only", style: TextStyle(fontSize: 12)),
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
                                itemBuilder: (context, index) => FadeSlideEntrance(
                                  index: index,
                                  child: _alertCard(filtered[index]),
                                ),
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

  Widget _karmaBadge(int karma) {
    final bool isPos = karma > 0;
    final bool isNeg = karma < 0;
    final Color fg = isPos
        ? AppColors.teal
        : isNeg
            ? Colors.redAccent
            : Colors.white70;
    final Color bg = isPos
        ? AppColors.teal.withValues(alpha: 0.14)
        : isNeg
            ? Colors.redAccent.withValues(alpha: 0.16)
            : Colors.white10;
    final String sign = isPos ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Text(
        "Karma $sign$karma",
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _statusBadge(String status, {String verificationSource = 'pending'}) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'verified':
        bg = AppColors.teal.withValues(alpha: 0.18);
        fg = AppColors.teal;
        label = verificationSource == 'community_consensus' ? 'Reported (7:3)' : 'Mod Verified';
        break;
      case 'under_investigation':
        bg = Colors.blue.withValues(alpha: 0.18);
        fg = Colors.lightBlueAccent;
        label = 'Investigating';
        break;
      case 'resolved':
        bg = Colors.green.withValues(alpha: 0.18);
        fg = Colors.greenAccent;
        label = 'Resolved';
        break;
      case 'rejected':
        bg = Colors.red.withValues(alpha: 0.18);
        fg = Colors.redAccent;
        label = 'Disputed';
        break;
      case 'pending':
      default:
        bg = Colors.amber.withValues(alpha: 0.18);
        fg = Colors.amberAccent;
        label = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
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
    final createdAt = report['createdAt'] as String? ?? report['reportedAt'] as String? ?? 'Unknown';
    final id = report['id'] as String? ?? 'N/A';
    final lat = report['latitude'];
    final lon = report['longitude'];
    final photoUrl = report['photoUrl'] as String?;
    final authorTag = report['authorTag'] as String? ?? 'Anonymous';
    final authorKarma = (report['authorKarma'] as num?)?.toInt() ?? 0;

    final commentController = TextEditingController();
    List<Map<String, dynamic>> comments = [];
    bool loadingComments = true;
    bool postingComment = false;
    bool startedFetch = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> loadComments() async {
            final loaded = await AuthService.instance.fetchReportComments(id);
            if (!ctx.mounted) return;
            setSheetState(() {
              comments = loaded;
              loadingComments = false;
            });
          }

          if (!startedFetch) {
            startedFetch = true;
            Future.microtask(loadComments);
          }

          final isMine = report['isMine'] == true;
          final upvotes = (report['upvotes'] as num?)?.toInt() ?? 0;
          final downvotes = (report['downvotes'] as num?)?.toInt() ?? 0;
          final totalVotes = upvotes + downvotes;
          final quorum = (report['quorumRequired'] as num?)?.toInt() ?? 5;
          final ratioPct = totalVotes > 0 ? ((upvotes / totalVotes) * 100).round() : 0;
          final status = report['status'] as String? ?? 'pending';
          final source = report['verificationSource'] as String? ?? 'pending';
          final myVote = report['myVote'] as String?;

          Future<void> castModalVote(String vote) async {
            final messenger = ScaffoldMessenger.of(context);
            final result = await AuthService.instance.voteReport(reportId: id, vote: vote);
            if (!mounted || !ctx.mounted) return;
            if (result != null) {
              setSheetState(() {
                report['upvotes'] = result['upvotes'] ?? report['upvotes'];
                report['downvotes'] = result['downvotes'] ?? report['downvotes'];
                report['myVote'] = result['myVote'] ?? vote;
                if (result['status'] != null) report['status'] = result['status'];
                if (result['verificationSource'] != null) {
                  report['verificationSource'] = result['verificationSource'];
                }
                if (result['authorKarma'] != null) {
                  report['authorKarma'] = result['authorKarma'];
                }
              });
              await _fetchRealCommunityAlerts();
            } else {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text("Vote could not be recorded — verify your account or connection."),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          Future<void> submitComment() async {
            final text = commentController.text.trim();
            if (text.isEmpty) return;
            setSheetState(() => postingComment = true);
            final created = await AuthService.instance.createReportComment(
              reportId: id,
              body: text,
            );
            if (!ctx.mounted) return;
            setSheetState(() => postingComment = false);
            if (created != null) {
              commentController.clear();
              setSheetState(() {
                comments = [...comments, created];
                report['commentCount'] = ((report['commentCount'] as num?)?.toInt() ?? 0) + 1;
              });
              if (mounted) setState(() {});
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AuthService.instance.lastCommentError ?? 'Sign in with verified account to comment.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          Future<void> voteOnComment(Map<String, dynamic> c, String vote) async {
            final commentId = c['id'] as String?;
            if (commentId == null) return;
            final res = await AuthService.instance.voteReportComment(
              reportId: id,
              commentId: commentId,
              vote: vote,
            );
            if (!ctx.mounted || res == null) return;
            setSheetState(() {
              c['upvotes'] = res['upvotes'] ?? c['upvotes'];
              c['downvotes'] = res['downvotes'] ?? c['downvotes'];
              c['myVote'] = res['myVote'] ?? vote;
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (ctx, scrollController) => Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(_typeIcon(type), color: _severityColor(type)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "$type Thread",
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      _statusBadge(status, verificationSource: source),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        "Posted anonymously as $authorTag",
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      _karmaBadge((report['authorKarma'] as num?)?.toInt() ?? authorKarma),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        if (photoUrl != null && photoUrl.isNotEmpty) ...[
                          _buildPhotoThumbnail(photoUrl),
                          const SizedBox(height: 12),
                        ],
                        Text(description, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.teal),
                            const SizedBox(width: 6),
                            Expanded(child: Text(location, style: const TextStyle(color: Colors.white70, fontSize: 12.5))),
                          ],
                        ),
                        if (lat != null && lon != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text("GPS: $lat, $lon • ${_formatTime(createdAt)}",
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                          ),
                        const SizedBox(height: 12),
                        // 7:3 Consensus Meter
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.glass,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    totalVotes == 0
                                        ? "Needs $quorum area votes (7:3 ratio)"
                                        : "$upvotes up • $downvotes down ($ratioPct% confirm)",
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    "$totalVotes/$quorum quorum",
                                    style: const TextStyle(color: AppColors.teal, fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: (totalVotes / quorum).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white12,
                                  color: ratioPct >= 70 ? AppColors.teal : AppColors.amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (AuthService.instance.currentUser != null)
                          isMine
                              ? const Text(
                                  "Your anonymous post — voting on your own report isn't allowed.",
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                                )
                              : Wrap(
                                  spacing: 8,
                                  children: [
                                    ScaleTapPop(
                                      onTap: () => castModalVote('confirm'),
                                      child: ActionChip(
                                        avatar: const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.teal),
                                        label: AnimatedMetricText(
                                          "Upvote ($upvotes)",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.teal,
                                            fontWeight: myVote == 'confirm' ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        backgroundColor: myVote == 'confirm'
                                            ? AppColors.teal.withValues(alpha: 0.22)
                                            : AppColors.teal.withValues(alpha: 0.08),
                                        side: BorderSide(color: AppColors.teal, width: myVote == 'confirm' ? 1.5 : 0.8),
                                        onPressed: () => castModalVote('confirm'),
                                      ),
                                    ),
                                    ScaleTapPop(
                                      onTap: () => castModalVote('decline'),
                                      child: ActionChip(
                                        avatar: const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.redAccent),
                                        label: AnimatedMetricText(
                                          "Downvote ($downvotes)",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.redAccent,
                                            fontWeight: myVote == 'decline' ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        backgroundColor: myVote == 'decline'
                                            ? Colors.redAccent.withValues(alpha: 0.22)
                                            : Colors.redAccent.withValues(alpha: 0.08),
                                        side: BorderSide(color: Colors.redAccent, width: myVote == 'decline' ? 1.5 : 0.8),
                                        onPressed: () => castModalVote('decline'),
                                      ),
                                    ),
                                  ],
                                ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white12),
                        Text(
                          "Public Comments (${comments.length})",
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (loadingComments)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (comments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              "No comments yet. Share what you saw nearby anonymously.",
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          )
                        else
                          for (int i = 0; i < comments.length; i++)
                            FadeSlideEntrance(
                              index: i,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.glass,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          comments[i]['authorTag'] as String? ?? 'Anonymous',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (comments[i]['isOp'] == true) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text("OP", style: TextStyle(color: AppColors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        _karmaBadge((comments[i]['authorKarma'] as num?)?.toInt() ?? 0),
                                        const Spacer(),
                                        Text(
                                          _formatTime(comments[i]['createdAt'] as String?),
                                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      comments[i]['body'] as String? ?? '',
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    if (AuthService.instance.currentUser != null && comments[i]['isMine'] != true) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: () => voteOnComment(comments[i], 'confirm'),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.arrow_upward_rounded,
                                                    size: 14,
                                                    color: comments[i]['myVote'] == 'confirm' ? AppColors.teal : Colors.white54,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    "${comments[i]['upvotes'] ?? 0}",
                                                    style: TextStyle(
                                                      color: comments[i]['myVote'] == 'confirm' ? AppColors.teal : Colors.white70,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          InkWell(
                                            onTap: () => voteOnComment(comments[i], 'decline'),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.arrow_downward_rounded,
                                                    size: 14,
                                                    color: comments[i]['myVote'] == 'decline' ? Colors.redAccent : Colors.white54,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    "${comments[i]['downvotes'] ?? 0}",
                                                    style: TextStyle(
                                                      color: comments[i]['myVote'] == 'decline' ? Colors.redAccent : Colors.white70,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  if (AuthService.instance.currentUser != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: "Comment anonymously...",
                                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                                filled: true,
                                fillColor: Colors.white10,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: AppColors.teal),
                            onPressed: postingComment ? null : submitComment,
                            icon: postingComment
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                          ),
                        ],
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "Sign in with a verified account to upvote or comment.",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 400), commentController.dispose);
    });
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
    final verificationSource = report['verificationSource'] as String? ?? 'pending';
    final authorTag = report['authorTag'] as String? ?? 'Anonymous';
    final authorKarma = (report['authorKarma'] as num?)?.toInt() ?? 0;
    final commentCount = (report['commentCount'] as num?)?.toInt() ?? 0;
    final upvotes = (report['upvotes'] as num?)?.toInt() ?? 0;
    final downvotes = (report['downvotes'] as num?)?.toInt() ?? 0;
    final totalVotes = upvotes + downvotes;
    final quorum = (report['quorumRequired'] as num?)?.toInt() ?? 5;
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
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "$severity • $type",
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  const Spacer(),
                  _statusBadge(status, verificationSource: verificationSource),
                ],
              ),

              const SizedBox(height: 6),

              Row(
                children: [
                  Text(authorTag, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  _karmaBadge(authorKarma),
                  const Spacer(),
                  if (totalVotes > 0)
                    Text(
                      "$upvotes/$totalVotes (${((upvotes / totalVotes) * 100).round()}% confirm)",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    )
                  else
                    Text(
                      "0/$quorum votes",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              if (photoUrl != null && photoUrl.isNotEmpty) ...[
                _buildPhotoThumbnail(photoUrl),
                const SizedBox(height: 8),
              ],

              Text(description, style: const TextStyle(fontSize: 14)),

              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (AuthService.instance.currentUser != null && report['isMine'] != true) ...[
                    _voteChip(
                      report,
                      vote: 'confirm',
                      icon: Icons.arrow_upward_rounded,
                      label: "Upvote $upvotes",
                      color: Colors.teal,
                    ),
                    _voteChip(
                      report,
                      vote: 'decline',
                      icon: Icons.arrow_downward_rounded,
                      label: "Downvote $downvotes",
                      color: Colors.redAccent,
                    ),
                  ] else if (report['isMine'] == true) ...[
                    const Text(
                      "Your post (↑↓ disabled)",
                      style: TextStyle(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
                    ),
                  ],
                  ActionChip(
                    avatar: const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.white70),
                    label: Text(
                      "Comments ($commentCount)",
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: const BorderSide(color: Colors.white12),
                    onPressed: () => _showReportDetails(context, report),
                  ),
                ],
              ),

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
    final isSelected = report['myVote'] == vote;
    return ActionChip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      backgroundColor: color.withOpacity(isSelected ? 0.22 : 0.08),
      side: BorderSide(
        color: color.withOpacity(isSelected ? 0.9 : 0.4),
        width: isSelected ? 1.5 : 1.0,
      ),
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
