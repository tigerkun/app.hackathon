import 'dart:math' as math;
import 'package:flutter/material.dart';
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
        AuthService.instance.fetchNearbyMarkers(
          latitude: _userLat,
          longitude: _userLng,
          radiusKm: 25.0,
        ),
        AuthService.instance.fetchReports(limit: 50),
      ]);

      if (mounted) {
        setState(() {
          _markers = results[0];
          _reports = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Could not fetch nearby safety data.";
          _isLoading = false;
        });
      }
    }
  }

  List<_MapPinItem> _getFilteredItems() {
    final List<_MapPinItem> items = [];

    // 1. Process safety markers
    for (final m in _markers) {
      final String category = (m['category'] ?? 'Verified Safe Zone').toString();
      final String name = (m['name'] ?? 'Safety Facility').toString();
      final double lat = (m['latitude'] is num) ? (m['latitude'] as num).toDouble() : _userLat;
      final double lng = (m['longitude'] is num) ? (m['longitude'] as num).toDouble() : _userLng;
      final String? address = m['address']?.toString();
      final bool isVerified = m['isVerified'] == true;

      double distanceKm = 0.0;
      if (m['distanceKm'] is num) {
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
      } else if (catLower.contains('safe') || catLower.contains('transit')) {
        icon = Icons.verified_user;
        color = AppColors.teal;
      } else {
        icon = Icons.security;
        color = Colors.cyan;
      }

      bool matchesFilter = false;
      if (_selectedFilter == "All") {
        matchesFilter = true;
      } else if (_selectedFilter == "Police" && catLower.contains('police')) {
        matchesFilter = true;
      } else if (_selectedFilter == "Hospitals" && (catLower.contains('hospital') || catLower.contains('medical'))) {
        matchesFilter = true;
      } else if (_selectedFilter == "Safe Zones" && (catLower.contains('safe') || catLower.contains('transit'))) {
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
    if (_selectedFilter == "All" || _selectedFilter == "Hazards") {
      for (final r in _reports) {
        final String type = (r['type'] ?? 'Hazard').toString();
        final String desc = (r['description'] ?? 'Community hazard report').toString();
        final String location = (r['location'] ?? 'Nearby').toString();
        final double? lat = (r['latitude'] is num) ? (r['latitude'] as num).toDouble() : null;
        final double? lng = (r['longitude'] is num) ? (r['longitude'] as num).toDouble() : null;

        if (lat == null || lng == null) continue;

        final double distanceKm = Geolocator.distanceBetween(_userLat, _userLng, lat, lng) / 1000.0;
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

    items.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return items;
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

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredItems();

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
              "GPS: ${_userLat.toStringAsFixed(4)}, ${_userLng.toStringAsFixed(4)}",
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
            _buildMapRadarCanvas(filteredItems),

          /// ---------------- TOP FILTER CHIPS ----------------
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip("All", count: _markers.length + _reports.length),
                  _filterChip("Police"),
                  _filterChip("Hospitals"),
                  _filterChip("Safe Zones"),
                  _filterChip("Hazards", count: _reports.length),
                ],
              ),
            ),
          ),

          /// ---------------- LOADING INDICATOR ----------------
          if (_isLoading)
            Positioned(
              top: 60,
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
              top: 60,
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
                const SizedBox(width: 12),
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

  Widget _buildMapRadarCanvas(List<_MapPinItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double centerX = constraints.maxWidth / 2;
        final double centerY = constraints.maxHeight / 2;

        // Scaling factor: 1 km = 28 screen logical pixels
        const double pxPerKm = 28.0;
        const double kmPerDegLat = 111.0;
        final double kmPerDegLng = 111.0 * math.cos(_userLat * math.pi / 180.0);

        return Stack(
          children: [
            // Dark vector road and radar background
            Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF070B14),
              child: CustomPaint(
                painter: _DarkVectorMapPainter(layer: "Safety"),
              ),
            ),

            // User Center Pin
            Positioned(
              left: centerX - 24,
              top: centerY - 24,
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
                      address: "Live GPS Fix (${_userLat.toStringAsFixed(4)}, ${_userLng.toStringAsFixed(4)})",
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

            // Dynamic Geo Pins mapped relative to user's real coordinates
            for (final item in items)
              _buildProjectedPin(item, centerX, centerY, pxPerKm, kmPerDegLat, kmPerDegLng, constraints),
          ],
        );
      },
    );
  }

  Widget _buildProjectedPin(
    _MapPinItem item,
    double centerX,
    double centerY,
    double pxPerKm,
    double kmPerDegLat,
    double kmPerDegLng,
    BoxConstraints constraints,
  ) {
    final double deltaLng = item.longitude - _userLng;
    final double deltaLat = item.latitude - _userLat;

    final double dX_km = deltaLng * kmPerDegLng;
    final double dY_km = -(deltaLat * kmPerDegLat); // Negative because screen Y increases downward

    double posX = centerX + (dX_km * pxPerKm) - 24;
    double posY = centerY + (dY_km * pxPerKm) - 24;

    // Clamp inside viewport margins so distant pins stay accessible on the radar edge
    final double minX = 16.0;
    final double maxX = constraints.maxWidth - 64.0;
    final double minY = 64.0;
    final double maxY = constraints.maxHeight - 140.0;

    final bool isClamped = posX < minX || posX > maxX || posY < minY || posY > maxY;
    posX = posX.clamp(minX, maxX);
    posY = posY.clamp(minY, maxY);

    return Positioned(
      left: posX,
      top: posY,
      child: GestureDetector(
        onTap: () => setState(() => _selectedItem = item),
        child: Opacity(
          opacity: isClamped ? 0.75 : 1.0,
          child: _InteractivePin(
            icon: item.icon,
            color: item.color,
            label: item.name.length > 14 ? "${item.name.substring(0, 12)}.." : item.name,
            distanceText: "${item.distanceKm.toStringAsFixed(1)}km",
          ),
        ),
      ),
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
                          "${item.distanceKm.toStringAsFixed(1)} km",
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
                      "${item.category} • ${item.distanceKm.toStringAsFixed(2)} km away",
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
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: isPulsing ? 12 : 6,
                spreadRadius: isPulsing ? 2 : 0,
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

class _DarkVectorMapPainter extends CustomPainter {
  final String layer;
  _DarkVectorMapPainter({required this.layer});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFF152238)
      ..strokeWidth = 5;

    final secondaryRoad = Paint()
      ..color = const Color(0xFF0E182A)
      ..strokeWidth = 2.5;

    // Major arteries
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), roadPaint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65), roadPaint);
    canvas.drawLine(Offset(size.width * 0.4, 0), Offset(size.width * 0.4, size.height), roadPaint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), roadPaint);

    // Diagonal arterial bypass
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width * 0.85, 0), secondaryRoad);

    // Minor streets grid
    for (double y = 40; y < size.height; y += 65) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), secondaryRoad);
    }
    for (double x = 40; x < size.width; x += 65) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), secondaryRoad);
    }

    // Safety Patrol Zone Polygon
    final safeZonePaint = Paint()
      ..color = const Color(0x182FE0C9)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.2)
      ..lineTo(size.width * 0.6, size.height * 0.25)
      ..lineTo(size.width * 0.55, size.height * 0.5)
      ..lineTo(size.width * 0.15, size.height * 0.45)
      ..close();
    canvas.drawPath(path, safeZonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
