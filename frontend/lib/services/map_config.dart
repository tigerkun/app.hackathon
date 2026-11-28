import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_colors.dart';

/// Tile provider configuration for the SafeSphere map (flutter_map).
///
/// Free by default: OpenStreetMap standard raster tiles with flutter_map's
/// built-in darkModeTilesContainerBuilder for dark-mode rendering — no account, no
/// API key, no card.
/// If prettier vector-style tiles are wanted later, pass a free MapTiler
/// key (100k loads/month) at build time:
///   flutter build apk --release --dart-define=SAFESPHERE_MAP_TILER_KEY=<key>
/// The same map code then switches providers automatically.
class SafeSphereMapConfig {
  /// Fallback map center (old Delhi default) used only before a real GPS fix —
  /// the UI never presents it as the user's location.
  static const double defaultLatitude = 28.6139;
  static const double defaultLongitude = 77.2090;

  static const String _mapTilerKey =
      String.fromEnvironment('SAFESPHERE_MAP_TILER_KEY');

  /// True when a MapTiler key was provided at build time.
  static bool get isMapTilerConfigured => _mapTilerKey.isNotEmpty;

  /// Raster tile URL template consumed by flutter_map's TileLayer.
  /// Default: standard OpenStreetMap tiles (free, no key). flutter_map's
  /// built-in darkModeTilesContainerBuilder is used to invert tiles into dark mode.
  /// NOTE: CARTO dark_all tiles now require an API key and are no longer
  /// used as the free default.
  static String get tileUrlTemplate => isMapTilerConfigured
      ? 'https://api.maptiler.com/maps/basic-v2/{z}/{x}/{y}.png?key=$_mapTilerKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// True when tiles are natively dark-themed (MapTiler, etc).
  /// When false, the map widget must apply darkModeTileBuilder.
  static bool get needsDarkFilter => !isMapTilerConfigured;

  /// Attribution text shown on the map (required by tile usage policies).
  static String get attribution => isMapTilerConfigured
      ? '© MapTiler © OpenStreetMap contributors'
      : '© OpenStreetMap contributors';

  static const String attributionUrl = 'https://www.openstreetmap.org/copyright';

  /// Package name sent as User-Agent with tile requests (OSM policy compliance).
  static const String userAgentPackageName = 'com.safesphere.app';
}

class LocationPreset {
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final String description;
  final IconData icon;

  const LocationPreset({
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.description,
    this.icon = Icons.location_city,
  });
}

class LocationService extends ChangeNotifier {
  static final LocationService _instance = LocationService._internal();
  static LocationService get instance => _instance;

  LocationService._internal();

  // Default initial location: Sehore, Madhya Pradesh
  double _currentLat = 23.1967;
  double _currentLng = 77.0819;
  String _locationLabel = "Sehore, Madhya Pradesh";
  bool _hasLiveGps = false;
  bool _isManualOverride = false;
  bool _isDetecting = false;
  String? _lastLocationError;

  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  String get locationLabel => _locationLabel;
  bool get hasLiveGps => _hasLiveGps;
  bool get isManualOverride => _isManualOverride;
  bool get hasResolvedLocation => _hasLiveGps || _isManualOverride;
  bool get isDetecting => _isDetecting;
  String? get lastLocationError => _lastLocationError;

  @visibleForTesting
  void resetForTesting() {
    _currentLat = 23.1967;
    _currentLng = 77.0819;
    _locationLabel = "Sehore, Madhya Pradesh";
    _hasLiveGps = false;
    _isManualOverride = false;
    _isDetecting = false;
    _lastLocationError = null;
    notifyListeners();
  }

  static const List<LocationPreset> presets = [
    LocationPreset(
      name: "Sehore Central",
      city: "Madhya Pradesh",
      latitude: 23.1967,
      longitude: 77.0819,
      description: "Your Live Location & Active Zone",
      icon: Icons.my_location,
    ),
    LocationPreset(
      name: "Connaught Place",
      city: "New Delhi",
      latitude: 28.6315,
      longitude: 77.2167,
      description: "Central Hub • Police & 24x7 Stores",
      icon: Icons.hub,
    ),
    LocationPreset(
      name: "AIIMS & South Extension",
      city: "New Delhi",
      latitude: 28.5672,
      longitude: 77.2100,
      description: "Emergency Medical & Trauma Zone",
      icon: Icons.local_hospital,
    ),
    LocationPreset(
      name: "Sector 18 Metro",
      city: "Noida",
      latitude: 28.5708,
      longitude: 77.3271,
      description: "Commercial Area & Transit Hub",
      icon: Icons.subway,
    ),
    LocationPreset(
      name: "Cyber City DLF",
      city: "Gurugram",
      latitude: 28.4952,
      longitude: 77.0894,
      description: "Corporate Hub & Late-Night Corridor",
      icon: Icons.business,
    ),
    LocationPreset(
      name: "Bandra West",
      city: "Mumbai",
      latitude: 19.0596,
      longitude: 72.8295,
      description: "Hill Road & Reclamation Safe Zone",
      icon: Icons.apartment,
    ),
    LocationPreset(
      name: "Indiranagar 100ft",
      city: "Bengaluru",
      latitude: 12.9784,
      longitude: 77.6408,
      description: "24x7 Active Commercial Corridor",
      icon: Icons.storefront,
    ),
    LocationPreset(
      name: "Koramangala 4th Block",
      city: "Bengaluru",
      latitude: 12.9352,
      longitude: 77.6245,
      description: "Transit & Women Safety Kiosk Zone",
      icon: Icons.shield,
    ),
    LocationPreset(
      name: "Shivaji Nagar / FC Road",
      city: "Pune",
      latitude: 18.5204,
      longitude: 73.8567,
      description: "University & Transit Helpdesk Area",
      icon: Icons.school,
    ),
    LocationPreset(
      name: "Hitec City / Madhapur",
      city: "Hyderabad",
      latitude: 17.4474,
      longitude: 78.3762,
      description: "IT Corridor & Safe Refuge Stations",
      icon: Icons.computer,
    ),
  ];

  /// Detects real device/emulator GPS position (prefers fresh GPS fix, falls
  /// back to last known position if current fix times out).
  Future<bool> detectLiveGps() async {
    _isDetecting = true;
    _lastLocationError = null;
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!_isManualOverride) _hasLiveGps = false;
        _lastLocationError = "Device Location / GPS is turned off.";
        _isDetecting = false;
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (!_isManualOverride) _hasLiveGps = false;
        _lastLocationError = "Location permission permanently denied. Enable in app settings.";
        _isDetecting = false;
        notifyListeners();
        return false;
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 6),
            ),
          ).timeout(const Duration(seconds: 6));
        } catch (_) {
          // Fresh fix unavailable/timed out; try cached last-known position
          pos = await Geolocator.getLastKnownPosition();
        }

        if (pos == null) {
          if (!_isManualOverride) _hasLiveGps = false;
          _lastLocationError = "Waiting for GPS satellite fix — try outdoors or pick a location.";
          _isDetecting = false;
          notifyListeners();
          return false;
        }

        _currentLat = pos.latitude;
        _currentLng = pos.longitude;
        _hasLiveGps = true;
        _isManualOverride = false;
        _lastLocationError = null;

        // Format label with readable city or live coordinates
        if ((_currentLat - 23.1967).abs() < 0.1 && (_currentLng - 77.0819).abs() < 0.1) {
          _locationLabel = "Sehore, Madhya Pradesh";
        } else {
          _locationLabel = "Live GPS: ${_currentLat.toStringAsFixed(2)}, ${_currentLng.toStringAsFixed(2)}";
        }

        _isDetecting = false;
        notifyListeners();
        return true;
      } else {
        if (!_isManualOverride) _hasLiveGps = false;
        _lastLocationError = "Location permission denied.";
      }
    } catch (_) {
      if (!_isManualOverride) _hasLiveGps = false;
      _lastLocationError = "Unable to acquire GPS fix right now.";
    }

    _isDetecting = false;
    notifyListeners();
    return false;
  }

  /// Sets location manually by preset or coordinates
  void setManualLocation({
    required double lat,
    required double lng,
    required String label,
  }) {
    _currentLat = lat;
    _currentLng = lng;
    _locationLabel = label;
    _hasLiveGps = false;
    _isManualOverride = true;
    _isDetecting = false;
    _lastLocationError = null;
    notifyListeners();
  }

  /// Displays the location selection modal bottom sheet
  static Future<void> showLocationPickerSheet(
    BuildContext context, {
    VoidCallback? onLocationChanged,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationPickerSheet(onLocationChanged: onLocationChanged),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  final VoidCallback? onLocationChanged;
  const _LocationPickerSheet({this.onLocationChanged});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _service = LocationService.instance;
  bool _isCustomExpanded = false;
  bool _isSearching = false;
  String? _searchError;
  List<Map<String, dynamic>> _searchResults = [];
  final _searchController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _latController.text = _service.currentLat.toStringAsFixed(4);
    _lngController.text = _service.currentLng.toStringAsFixed(4);
    _nameController.text = _service.isManualOverride ? _service.locationLabel : "Custom Spot";
  }

  @override
  void dispose() {
    _searchController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', 'search', {
        'q': query,
        'format': 'json',
        'limit': '5',
      });
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, SafeSphereMapConfig.userAgentPackageName);
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await utf8.decoder.bind(res).join();
      if (!mounted) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(body);
        if (decoded is List) {
          setState(() {
            _searchResults = decoded.whereType<Map<String, dynamic>>().toList();
            _searchError = _searchResults.isEmpty ? "No places found for '$query'" : null;
            _isSearching = false;
          });
          return;
        }
      }
      setState(() {
        _searchError = "Search unavailable right now";
        _isSearching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchError = "Could not reach place search";
          _isSearching = false;
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  void _applyAndClose(double lat, double lng, String label) {
    _service.setManualLocation(lat: lat, lng: lng, label: label);
    widget.onLocationChanged?.call();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF101A33),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.teal, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Location updated: $label",
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.my_location, color: AppColors.teal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // Expanded: the subtitle ("...police, hospitals & 24x7
                    // stores") must wrap on narrow viewports instead of
                    // pushing the header Row 112px past the sheet edge.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Choose Your Location",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "Set area to discover nearby police, hospitals & 24x7 stores",
                            style: TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 16),
              // Active Location Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !_service.hasResolvedLocation
                          ? AppColors.amber.withValues(alpha: 0.5)
                          : (_service.isManualOverride
                              ? AppColors.blue.withValues(alpha: 0.5)
                              : AppColors.teal.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        !_service.hasResolvedLocation
                            ? Icons.location_off_outlined
                            : (_service.isManualOverride ? Icons.edit_location_alt : Icons.gps_fixed),
                        color: !_service.hasResolvedLocation
                            ? AppColors.amber
                            : (_service.isManualOverride ? AppColors.blue : AppColors.teal),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  !_service.hasResolvedLocation
                                      ? "GPS UNAVAILABLE"
                                      : (_service.isManualOverride ? "MANUAL OVERRIDE" : "DEVICE LOCATION"),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: !_service.hasResolvedLocation
                                        ? AppColors.amber
                                        : (_service.isManualOverride ? AppColors.blue : AppColors.teal),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              !_service.hasResolvedLocation
                                  ? (_service.lastLocationError ?? "Tap GPS Fix or pick an area below")
                                  : _service.locationLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              !_service.hasResolvedLocation
                                  ? "Showing all areas until location is set"
                                  : "Lat: ${_service.currentLat.toStringAsFixed(4)}, Lon: ${_service.currentLng.toStringAsFixed(4)}",
                              style: const TextStyle(fontSize: 11, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: _service.isDetecting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                              )
                            : const Icon(Icons.refresh, color: AppColors.teal, size: 14),
                        label: const Text(
                          "GPS Fix",
                          style: TextStyle(color: AppColors.teal, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _service.isDetecting
                            ? null
                            : () async {
                                final nav = Navigator.of(context);
                                final success = await _service.detectLiveGps();
                                if (!mounted) return;
                                if (success) {
                                  widget.onLocationChanged?.call();
                                  nav.pop();
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
              // Search by City / Area + Preset Locations List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchPlace(),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Search city, area, or landmark (e.g. Sehore, Bhopal)...",
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          prefixIcon: const Icon(Icons.search, color: AppColors.teal, size: 18),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward, color: AppColors.teal, size: 18),
                                  tooltip: "Search",
                                  onPressed: _searchPlace,
                                ),
                          filled: true,
                          fillColor: const Color(0xFF161F30),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.teal),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    if (_searchError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          _searchError!,
                          style: const TextStyle(color: AppColors.amber, fontSize: 12),
                        ),
                      ),
                    if (_searchResults.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                          "Search Results",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.teal,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      ..._searchResults.map((place) {
                        final displayName = (place['display_name'] ?? 'Selected Location').toString();
                        final shortLabel = displayName.split(',').take(2).map((s) => s.trim()).join(', ');
                        final lat = double.tryParse((place['lat'] ?? '').toString());
                        final lon = double.tryParse((place['lon'] ?? '').toString());
                        if (lat == null || lon == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => _applyAndClose(lat, lon, shortLabel.isNotEmpty ? shortLabel : displayName),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.place, color: AppColors.teal, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.teal, size: 18),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8, top: 4),
                      child: Text(
                        "Popular Safety Corridors & Cities",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...LocationService.presets.map((p) {
                      final isSelected = _service.hasResolvedLocation &&
                          (_service.currentLat - p.latitude).abs() < 0.001 &&
                          (_service.currentLng - p.longitude).abs() < 0.001;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _applyAndClose(p.latitude, p.longitude, "${p.name}, ${p.city}"),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.teal.withValues(alpha: 0.15)
                                  : const Color(0xFF161F30),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppColors.teal : Colors.white10,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.teal.withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    p.icon,
                                    size: 18,
                                    color: isSelected ? AppColors.teal : Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${p.name} • ${p.city}",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? AppColors.teal : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        p.description,
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, color: AppColors.teal, size: 18)
                                else
                                  const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    // Custom Coordinates Input Section
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _isCustomExpanded = !_isCustomExpanded),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161F30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.pin_drop_outlined, color: AppColors.amber, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Enter Custom Coordinates (Lat / Lng)",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                            Icon(
                              _isCustomExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isCustomExpanded) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131D2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: "Location Label / Name",
                                labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                                prefixIcon: const Icon(Icons.label_outline, color: Colors.white54, size: 18),
                                filled: true,
                                fillColor: Colors.black26,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _latController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "Latitude",
                                      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                                      prefixIcon: const Icon(Icons.north, color: Colors.white54, size: 16),
                                      filled: true,
                                      fillColor: Colors.black26,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _lngController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "Longitude",
                                      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                                      prefixIcon: const Icon(Icons.east, color: Colors.white54, size: 16),
                                      filled: true,
                                      fillColor: Colors.black26,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.teal,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text("Apply Custom Location", style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  final lat = double.tryParse(_latController.text.trim());
                                  final lng = double.tryParse(_lngController.text.trim());
                                  final label = _nameController.text.trim().isNotEmpty
                                      ? _nameController.text.trim()
                                      : "Custom (${lat?.toStringAsFixed(2)}, ${lng?.toStringAsFixed(2)})";
                                  if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                                    _applyAndClose(lat, lng, label);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Please enter valid latitude (-90 to 90) and longitude (-180 to 180)"),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

