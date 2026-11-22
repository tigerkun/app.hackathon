import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_colors.dart';
import '../services/map_config.dart';
import '../services/auth_service.dart';

class SafetyMapPage extends StatefulWidget {
  const SafetyMapPage({super.key});

  @override
  State<SafetyMapPage> createState() => _SafetyMapPageState();
}

class _SafetyMapPageState extends State<SafetyMapPage> {
  String _selectedFilter = "All"; // All | Police | Hospitals | Safe Zones | Hazards
  bool _isLocating = false;
  bool _isLoading = false;
  bool _isListView = false;
  String? _errorMessage;

  double _userLat = SafeSphereMapConfig.defaultLatitude;
  double _userLng = SafeSphereMapConfig.defaultLongitude;
  // False until a real GPS fix arrives — never present the Delhi default as
  // the user's location (nearby markers, distances, and the AppBar label all
  // depend on this flag).
  bool _hasGpsFix = false;  

  List<Map<String, dynamic>> _markers = [];
  List<Map<String, dynamic>> _reports = [];
  _MapPinItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    await _centerUserLocation();
    await _loadMapData();
  }

  Future<void> _centerUserLocation() async {
    setState(() => _isLocating = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
          if (mounted) setState(() => _isLocating = false);
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      ).timeout(const Duration(seconds: 4));

      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
          _hasGpsFix = true;
        });
      }
    } catch (_) {
      // Keep default coordinates
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _hasGpsFix
            ? AuthService.instance.fetchNearbyMarkers(
                latitude: _userLat,
                longitude: _userLng,
                radiusKm: 10,
              )
            : Future<List<Map<String, dynamic>>>.value(const []),
        AuthService.instance.fetchReports(limit: 50),
      ]);

      if (!mounted) return;
      // Per-endpoint flags: a successful reports fetch must not mask a
      // markers failure (and vice versa) when both run concurrently.
      if (_hasGpsFix && AuthService.instance.markersFetchFailed && results[0].isEmpty) {
        setState(() {
          _errorMessage = "Could not fetch nearby safety data.";
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _markers = results[0];
        _reports = results[1];
        _isLoading = false;
        _errorMessage = _hasGpsFix
            ? null
            : "Location permission off — showing community reports only. Enable GPS for nearby markers.";
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Could not fetch nearby safety data.";
          _isLoading = false;
        });
      }
    }
  }

  // applyFilter=false returns EVERY loaded pin — the near-me strip needs the
  // unfiltered set or choosing "Police" would hide the nearest hospital.
  List<_MapPinItem> _getFilteredItems({bool applyFilter = true}) {
    final List<_MapPinItem> items = [];

    // 1. Process safety markers
    for (final m in _markers) {
      final String category = (m['category'] ?? 'Verified Safe Zone').toString();
      final String name = (m['name'] ?? 'Safety Facility').toString();
      // Reject non-finite/out-of-range coordinates — previously a marker with
      // a missing lat/lng silently rendered ON TOP of the user's position.
      final rawLat = m['latitude'];
      final rawLng = m['longitude'];
      if (rawLat is! num || rawLng is! num) continue;
      final lat = rawLat.toDouble();
      final lng = rawLng.toDouble();
      if (!lat.isFinite || !lng.isFinite || lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      final String? address = m['address']?.toString();
      final bool isVerified = m['isVerified'] == true;

      double distanceKm;
      if (!_hasGpsFix) {
        // Delhi fallback coords are NOT the user's position — distance is
        // honestly unknown (-1 sentinel), never a fabricated kilometre value.
        distanceKm = -1;
      } else if (m['distanceKm'] is num) {
        distanceKm = (m['distanceKm'] as num).toDouble();
      } else {
        distanceKm = Geolocator.distanceBetween(_userLat, _userLng, lat, lng) / 1000.0;
      }

      final IconData icon;
      final Color color;
      final String catLower = category.toLowerCase();

      if (catLower.contains('police')) {
        icon = Icons.local_police;
        color = AppColors.blue;
      } else if (catLower.contains('hospital') || catLower.contains('medical')) {
        icon = Icons.local_hospital;
        color = AppColors.red;
      } else if (catLower.contains('24x7') || catLower.contains('store')) {
        // M4: 24x7 Store — always-open refuge (cashier, lighting, CCTV, footfall)
        icon = Icons.storefront;
        color = AppColors.green;
      } else if (catLower.contains('safe') || catLower.contains('transit')) {
        icon = Icons.verified_user;
        color = AppColors.teal;
      } else {
        icon = Icons.security;
        color = Colors.cyan;
      }

      bool matchesFilter = !applyFilter;
      if (!matchesFilter && _selectedFilter == "All") {
        matchesFilter = true;
      } else if (!matchesFilter && _selectedFilter == "Police" && catLower.contains('police')) {
        matchesFilter = true;
      } else if (!matchesFilter && _selectedFilter == "Hospitals" && (catLower.contains('hospital') || catLower.contains('medical'))) {
        matchesFilter = true;
      } else if (!matchesFilter && _selectedFilter == "Stores" && (catLower.contains('24x7') || catLower.contains('store'))) {
        matchesFilter = true;
      } else if (!matchesFilter && _selectedFilter == "Safe Zones" && (catLower.contains('safe') || catLower.contains('transit'))) {
        matchesFilter = true;
      }

      if (matchesFilter) {
        items.add(_MapPinItem(
          id: (m['id'] ?? name).toString(),
          name: name,
          category: category,
          latitude: lat,
          longitude: lng,
          distanceKm: distanceKm,
          address: address,
          isVerified: isVerified,
          isHazardReport: false,
          icon: icon,
          color: color,
        ));
      }
    }

    // 2. Process community hazard reports
    if (!applyFilter || _selectedFilter == "All" || _selectedFilter == "Hazards") {
      for (final r in _reports) {
        final String type = (r['type'] ?? 'Hazard').toString();
        final String desc = (r['description'] ?? 'Community hazard report').toString();
        final String location = (r['location'] ?? 'Nearby').toString();
        final rawLat = r['latitude'];
        final rawLng = r['longitude'];
        if (rawLat is! num || rawLng is! num) continue;
        final lat = rawLat.toDouble();
        final lng = rawLng.toDouble();
        if (!lat.isFinite || !lng.isFinite || lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;

        final double distanceKm = _hasGpsFix
            ? Geolocator.distanceBetween(_userLat, _userLng, lat, lng) / 1000.0
            : -1;
        final bool isVerified = (r['status'] == 'verified');

        items.add(_MapPinItem(
          id: (r['id'] ?? desc).toString(),
          name: "$type Incident",
          category: type,
          latitude: lat,
          longitude: lng,
          distanceKm: distanceKm,
          address: "$location — $desc",
          isVerified: isVerified,
          isHazardReport: true,
          icon: Icons.warning_amber_rounded,
          color: isVerified ? AppColors.amber : Colors.orange,
        ));
      }
    }

    // Unknown distances (-1, no GPS fix) sort last rather than posing as
    // "0.0 km away".
    double sortKey(_MapPinItem i) => i.distanceKm < 0 ? double.infinity : i.distanceKm;
    items.sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    return items;
  }

  /// Honest distance label — "-1" means GPS was unavailable, so no distance
  /// claim is made at all.
  String _fmtDistance(double km) {
    if (km < 0) return 'distance unknown';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  Future<void> _openExternalDirections(double destLat, double destLng) async {
    final uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse("tel:$phone");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openExternalGoogleMap() async {
    final uri = Uri.parse("https://www.google.com/maps/@$_userLat,$_userLng,15z");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// F5-5: Shows a dialog allowing authenticated users to submit a safety marker.
  Future<void> _showSubmitMarkerDialog() async {
    if (!AuthService.instance.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sign in to submit new safety markers")),
      );
      return;
    }

    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final noteController = TextEditingController();
    String selectedCategory = 'Police Station';
    double markerLat = _userLat;
    double markerLng = _userLng;
    final latController = TextEditingController(text: markerLat.toStringAsFixed(6));
    final lngController = TextEditingController(text: markerLng.toStringAsFixed(6));
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF131D31),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.add_location_alt, color: AppColors.teal),
                SizedBox(width: 8),
                Text(
                  "Submit Safety Marker",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Submitted markers will be reviewed and verified by moderators.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Facility / Location Name *",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: "e.g. Connaught Place Police Post",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Category *",
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Police Station', child: Text('Police Station')),
                      DropdownMenuItem(value: 'Hospital', child: Text('Hospital / Clinic')),
                      DropdownMenuItem(value: 'Verified Safe Zone', child: Text('Safe Zone / Shelter')),
                      DropdownMenuItem(value: 'Well-lit Transit Hub', child: Text('Transit Hub')),
                      DropdownMenuItem(value: '24x7 Store', child: Text('24x7 Store (always open)')),
                      DropdownMenuItem(value: 'Caution Area', child: Text('Caution Area')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Latitude *",
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null) markerLat = parsed;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lngController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Longitude *",
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null) markerLng = parsed;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Address (Optional)",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: "Street name or landmark",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: "Note for Moderators (Optional)",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: "e.g. 24/7 security guard on duty",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter a facility name")),
                          );
                          return;
                        }

                        final lat = double.tryParse(latController.text.trim());
                        final lng = double.tryParse(lngController.text.trim());
                        if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter valid GPS coordinates")),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          final res = await AuthService.instance.createMarker(
                            name: name,
                            category: selectedCategory,
                            latitude: lat,
                            longitude: lng,
                            address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                            note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                          );

                          if (!context.mounted) return;
                          Navigator.pop(ctx);

                          if (res != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Marker submitted — pending verification by moderators"),
                                backgroundColor: AppColors.teal,
                              ),
                            );
                            await _loadMapData();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Failed to submit marker. Please try again."),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("An error occurred while submitting marker"),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text("Submit", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      // Dialog-local controllers must not outlive the dialog.
      nameController.dispose();
      addressController.dispose();
      noteController.dispose();
      latController.dispose();
      lngController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredItems();
    // Near-me strip always sees the UNFILTERED set — category filters must
    // not hide the nearest hospital/police/store chips.
    final allPinItems = _getFilteredItems(applyFilter: false);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Safety Map", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              _hasGpsFix
                  ? "GPS: ${_userLat.toStringAsFixed(4)}, ${_userLng.toStringAsFixed(4)}"
                  : "GPS: off",
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isListView ? Icons.map_outlined : Icons.list_alt),
            tooltip: _isListView ? "Show Map View" : "Show Directory View",
            onPressed: () => setState(() => _isListView = !_isListView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Safety Data",
            onPressed: () async {
              await _centerUserLocation();
              await _loadMapData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: "Open in Google Maps",
            onPressed: _openExternalGoogleMap,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isListView)
            _buildDirectoryList(filteredItems)
          else
            _buildLiveMap(filteredItems),

          /// ---------------- TOP FILTER CHIPS + NEAR-ME SERVICE STRIP (M4) --
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip("All", count: _markers.length + _reports.length),
                      _filterChip("Police"),
                      _filterChip("Hospitals"),
                      _filterChip("Stores"),
                      _filterChip("Safe Zones"),
                      _filterChip("Hazards", count: _reports.length),
                    ],
                  ),
                ),
                if (_hasGpsFix && !_isListView) _buildNearMeStrip(allPinItems),
              ],
            ),
          ),

          /// ---------------- LOADING INDICATOR ----------------
          if (_isLoading)
            Positioned(
              top: _hasGpsFix && !_isListView ? 112 : 60,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101A33).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal)),
                      SizedBox(width: 10),
                      Text("Updating verified pins...", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          /// ---------------- ERROR BANNER ----------------
          if (_errorMessage != null)
            Positioned(
              top: _hasGpsFix && !_isListView ? 112 : 60,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 12))),
                    TextButton(
                      onPressed: _loadMapData,
                      child: const Text("RETRY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),

          /// ---------------- SELECTED MARKER DETAILS CARD ----------------
          if (_selectedItem != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 84,
              child: _buildDetailsCard(_selectedItem!),
            ),

          /// ---------------- GPS & ACTION BUTTONS ----------------
          Positioned(
            right: 16,
            bottom: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: "centerGps",
                  backgroundColor: const Color(0xFF101A33),
                  onPressed: () async {
                    await _centerUserLocation();
                    await _loadMapData();
                  },
                  child: _isLocating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                      : const Icon(Icons.my_location, color: AppColors.teal),
                ),
                const SizedBox(width: 8),
                // F5-5: Submit safety marker FAB (authenticated users only)
                if (AuthService.instance.isAuthenticated) ...[
                  FloatingActionButton.small(
                    heroTag: "submitMarker",
                    backgroundColor: AppColors.teal,
                    tooltip: "Submit a safety marker",
                    onPressed: _showSubmitMarkerDialog,
                    child: const Icon(Icons.add_location_alt, color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 8),
                ],
                FloatingActionButton.extended(
                  heroTag: "reportLoc",
                  backgroundColor: AppColors.amber,
                  icon: const Icon(Icons.flag, color: Colors.black, size: 18),
                  label: const Text(
                    "Report Near Me",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => Navigator.pushNamed(context, '/report'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// M4: "Near me" service strip — the nearest verified refuge per critical
  /// category, one tap to select it on the map. Only shown with a real GPS
  /// fix (never against the Delhi default), and honestly shows "none found"
  /// when a category is missing from the loaded set.
  Widget _buildNearMeStrip(List<_MapPinItem> items) {
    final criticalCategories = [
      ("Police", Icons.local_police, "police"),
      ("Hospital", Icons.local_hospital, "hospital|medical"),
      ("24x7", Icons.storefront, "24x7|store"),
      ("Safe zone", Icons.verified_user, "safe|transit"),
    ];

    final chips = <Widget>[];
    for (final (label, icon, patterns) in criticalCategories) {
      final patternsList = patterns.split('|');
      _MapPinItem? nearest;
      for (final item in items) {
        if (item.isHazardReport) continue;
        final cat = item.category.toLowerCase();
        final matches = patternsList.any((p) => cat.contains(p));
        if (matches) {
          nearest = item; // items are pre-sorted by distance
          break;
        }
      }
      chips.add(
        GestureDetector(
          onTap: nearest == null ? null : () => setState(() => _selectedItem = nearest),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: nearest != null
                  ? const Color(0xFF101A33).withValues(alpha: 0.92)
                  : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: nearest != null
                    ? AppColors.teal.withValues(alpha: 0.5)
                    : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: nearest != null ? AppColors.teal : Colors.white24),
                const SizedBox(width: 5),
                Text(
                  nearest != null
                      ? "$label ${nearest.distanceKm < 1 ? "${(nearest.distanceKm * 1000).round()}m" : "${nearest.distanceKm.toStringAsFixed(1)}km"}"
                      : "$label — none loaded",
                  style: TextStyle(
                    color: nearest != null ? Colors.white : Colors.white24,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final chip in chips) ...[chip, const SizedBox(width: 8)],
        ]),
      ),
    );
  }

  /// Real pannable/zoomable map (flutter_map + OpenStreetMap-derived raster
  /// tiles). Free by default: no API key, no card, no billing account.
  Widget _buildLiveMap(List<_MapPinItem> items) {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(_userLat, _userLng),
            initialZoom: 13.5,
            minZoom: 3.0,
            maxZoom: 18.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onTap: (_, __) {
              if (_selectedItem != null) {
                setState(() => _selectedItem = null);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: SafeSphereMapConfig.tileUrlTemplate,
              userAgentPackageName: SafeSphereMapConfig.userAgentPackageName,
              maxNativeZoom: 19,
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  SafeSphereMapConfig.attribution,
                  onTap: () => launchUrl(
                    Uri.parse(SafeSphereMapConfig.attributionUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
            if (_hasGpsFix)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_userLat, _userLng),
                    radius: 400,
                    useRadiusInMeter: true,
                    color: AppColors.teal.withValues(alpha: 0.14),
                    borderColor: AppColors.teal.withValues(alpha: 0.45),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            // M4: guidance line — straight ("as the crow flies") path from the
            // user's fix to the selected pin. Honest: it is NOT turn-by-turn
            // routing; the details card still offers real external directions.
            // Caution Areas are hazards to avoid, not destinations — never
            // draw a guidance line toward one.
            if (_hasGpsFix && _selectedItem != null && !_selectedItem!.isHazardReport && _selectedItem!.id != "you"
                && !_selectedItem!.category.toLowerCase().contains('caution'))
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      LatLng(_userLat, _userLng),
                      LatLng(_selectedItem!.latitude, _selectedItem!.longitude),
                    ],
                    color: AppColors.teal.withValues(alpha: 0.75),
                    strokeWidth: 3.5,
                    pattern: StrokePattern.dashed(segments: const [10, 7]),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // User location pin
                Marker(
                  point: LatLng(_userLat, _userLng),
                  width: 48,
                  height: 48,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedItem = _MapPinItem(
                          id: "you",
                          name: "Your Live Location",
                          category: "Current Location",
                          latitude: _userLat,
                          longitude: _userLng,
                          distanceKm: 0.0,
                          address:
                              "Live GPS Fix (${_userLat.toStringAsFixed(4)}, ${_userLng.toStringAsFixed(4)})",
                          isVerified: true,
                          isHazardReport: false,
                          icon: Icons.my_location,
                          color: AppColors.teal,
                        );
                      });
                    },
                    child: const _InteractivePin(
                      icon: Icons.my_location,
                      color: AppColors.teal,
                      label: "You",
                      isPulsing: true,
                    ),
                  ),
                ),
                // Verified safety markers + citizen hazard reports at true coordinates
                for (final item in items)
                  Marker(
                    point: LatLng(item.latitude, item.longitude),
                    width: 48,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedItem = item),
                      child: _InteractivePin(
                        icon: item.icon,
                        color: item.color,
                        label:
                            item.name.length > 14 ? "${item.name.substring(0, 12)}.." : item.name,
                        distanceText: _fmtDistance(item.distanceKm),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // Honest GPS-off indicator: the map centers on the Delhi fallback
        // until a real fix arrives — never presented as the user's location.
        if (!_hasGpsFix)
          Positioned(
            top: 56,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_off, size: 12, color: AppColors.amber),
                  SizedBox(width: 5),
                  Text(
                    "GPS off — showing default area",
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDirectoryList(List<_MapPinItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              "No ${_selectedFilter == "All" ? "" : _selectedFilter} pins found nearby.",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh"),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: Colors.black),
              onPressed: _loadMapData,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 60, bottom: 90, left: 16, right: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color(0xFF101A33),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: item.color.withValues(alpha: 0.3)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _selectedItem = item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: item.color, width: 1.5),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.isVerified)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified, size: 14, color: AppColors.teal),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.address ?? "${item.category} • Lat: ${item.latitude.toStringAsFixed(3)}, Lng: ${item.longitude.toStringAsFixed(3)}",
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${_fmtDistance(item.distanceKm)}",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: item.color),
                        ),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        icon: const Icon(Icons.directions, color: AppColors.teal, size: 20),
                        tooltip: "Directions",
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _openExternalDirections(item.latitude, item.longitude),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsCard(_MapPinItem item) {
    final bool isPolice = item.category.toLowerCase().contains('police');
    final bool isHospital = item.category.toLowerCase().contains('hospital') || item.category.toLowerCase().contains('medical');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F182E).withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.color.withValues(alpha: 0.6)),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      "${item.category} • ${_fmtDistance(item.distanceKm)} away",
                      style: TextStyle(fontSize: 11, color: item.color),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                onPressed: () => setState(() => _selectedItem = null),
              ),
            ],
          ),
          if (item.address != null) ...[
            const SizedBox(height: 8),
            Text(item.address!, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.directions, size: 16),
                  label: const Text("Directions", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openExternalDirections(item.latitude, item.longitude),
                ),
              ),
              if (isPolice || isHospital) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call, size: 16),
                    label: Text(
                      isPolice ? "Call 112" : "Call 108",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: item.color,
                      side: BorderSide(color: item.color),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _callPhone(isPolice ? "112" : "108"),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, {int? count}) {
    final active = _selectedFilter == label;
    final display = count != null && count > 0 ? "$label ($count)" : label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(display),
        selected: active,
        onSelected: (_) => setState(() => _selectedFilter = label),
        backgroundColor: const Color(0xFF101A33),
        selectedColor: AppColors.teal.withValues(alpha: 0.25),
        labelStyle: TextStyle(
          color: active ? AppColors.teal : Colors.white70,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        side: BorderSide(color: active ? AppColors.teal : Colors.white12),
      ),
    );
  }
}

class _MapPinItem {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? address;
  final bool isVerified;
  final bool isHazardReport;
  final IconData icon;
  final Color color;

  const _MapPinItem({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.address,
    required this.isVerified,
    required this.isHazardReport,
    required this.icon,
    required this.color,
  });
}

class _InteractivePin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? distanceText;
  final bool isPulsing;

  const _InteractivePin({
    required this.icon,
    required this.color,
    required this.label,
    this.distanceText,
    this.isPulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            // M4: category-tinted glow halo — two stacked shadows give the
            // pins a soft outer aura so refuges pop on dark tiles at night.
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55),
                blurRadius: isPulsing ? 16 : 9,
                spreadRadius: isPulsing ? 3 : 1,
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.20),
                blurRadius: 22,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (distanceText != null)
                Text(
                  distanceText!,
                  style: const TextStyle(fontSize: 8, color: Colors.white70),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
