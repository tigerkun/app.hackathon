import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_colors.dart';
import '../services/map_config.dart';

class SafetyMapPage extends StatefulWidget {
  const SafetyMapPage({super.key});

  @override
  State<SafetyMapPage> createState() => _SafetyMapPageState();
}

class _SafetyMapPageState extends State<SafetyMapPage> {
  String _selectedFilter = "All";
  String _mapLayer = "Safety"; // Safety | Dark Street | Satellite
  bool _isLocating = false;
  double _userLat = SafeSphereMapConfig.defaultLatitude;
  double _userLng = SafeSphereMapConfig.defaultLongitude;
  String? _selectedMarkerInfo;

  @override
  void initState() {
    super.initState();
    _centerUserLocation();
  }

  Future<void> _centerUserLocation() async {
    setState(() => _isLocating = true);
    try {
      final hasPermission = await Geolocator.checkPermission();
      if (hasPermission == LocationPermission.always || hasPermission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 4)),
        ).timeout(const Duration(seconds: 4));
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
      }
    } catch (_) {
      // Keep default
    } finally {
      if (mounted) setState(() => _isLocating = false);
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
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text("Safety Map"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: "Open in Google Maps",
            onPressed: _openExternalGoogleMap,
          ),
        ],
      ),
      body: Stack(
        children: [
          /// ---------------- MAP CANVAS ----------------
          Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF070B14),
            child: CustomPaint(
              painter: _DarkVectorMapPainter(layer: _mapLayer),
            ),
          ),

          /// ---------------- MARKERS LAYER ----------------
          // 1. User Position Marker
          Positioned(
            top: 240,
            left: 170,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMarkerInfo = "Your Live Location\nLat: ${_userLat.toStringAsFixed(4)}, Lng: ${_userLng.toStringAsFixed(4)}";
                });
              },
              child: _InteractivePin(
                icon: Icons.my_location,
                color: AppColors.teal,
                label: "You",
                isPulsing: true,
              ),
            ),
          ),

          // 2. Police Station Marker
          if (_selectedFilter == "All" || _selectedFilter == "Police")
            Positioned(
              top: 140,
              left: 90,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMarkerInfo = "City Central Police Booth\n• Active 24/7 Patrol • Dial 112";
                  });
                },
                child: const _InteractivePin(
                  icon: Icons.local_police,
                  color: AppColors.blue,
                  label: "Police Post",
                ),
              ),
            ),

          // 3. Hospital Marker
          if (_selectedFilter == "All" || _selectedFilter == "Hospitals")
            Positioned(
              top: 340,
              right: 60,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMarkerInfo = "Metropolitan Emergency Trauma Unit\n• Ambulance Ready: Dial 108";
                  });
                },
                child: const _InteractivePin(
                  icon: Icons.local_hospital,
                  color: AppColors.red,
                  label: "Hospital",
                ),
              ),
            ),

          // 4. Hazard: Poor Lighting
          if (_selectedFilter == "All" || _selectedFilter == "Hazards")
            Positioned(
              top: 180,
              right: 80,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMarkerInfo = "Caution: Street Light Outage\nReported 30 mins ago • 3 verifications";
                  });
                },
                child: const _InteractivePin(
                  icon: Icons.lightbulb_outline,
                  color: AppColors.amber,
                  label: "Dark Stretch",
                ),
              ),
            ),

          // 5. Hazard: Suspicious Activity
          if (_selectedFilter == "All" || _selectedFilter == "Hazards")
            Positioned(
              top: 290,
              left: 60,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMarkerInfo = "Warning: Suspicious Group\nReported 1 hr ago near Market Lane";
                  });
                },
                child: const _InteractivePin(
                  icon: Icons.visibility,
                  color: Colors.orange,
                  label: "Caution Zone",
                ),
              ),
            ),

          /// ---------------- FILTER CHIPS ----------------
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip("All"),
                  _filterChip("Police"),
                  _filterChip("Hospitals"),
                  _filterChip("Hazards"),
                ],
              ),
            ),
          ),

          /// ---------------- SELECTED MARKER BANNER ----------------
          if (_selectedMarkerInfo != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 90,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101A33).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.teal.withValues(alpha: 0.5)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.teal, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedMarkerInfo!,
                        style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.3),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                      onPressed: () => setState(() => _selectedMarkerInfo = null),
                    ),
                  ],
                ),
              ),
            ),

          /// ---------------- GPS RE-CENTER & LAYER CONTROLS ----------------
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: "centerGps",
                  backgroundColor: const Color(0xFF101A33),
                  onPressed: _centerUserLocation,
                  child: _isLocating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                      : const Icon(Icons.my_location, color: AppColors.teal),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: "reportLoc",
                  backgroundColor: AppColors.amber,
                  icon: const Icon(Icons.flag, color: Colors.black, size: 18),
                  label: const Text("Report Near Pin", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => Navigator.pushNamed(context, '/report'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label) {
    final active = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
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

class _InteractivePin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool isPulsing;

  const _InteractivePin({
    required this.icon,
    required this.color,
    required this.label,
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
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1),
            ],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
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
    // Road Grid
    final roadPaint = Paint()
      ..color = const Color(0xFF152238)
      ..strokeWidth = 6;

    final secondaryRoad = Paint()
      ..color = const Color(0xFF0E182A)
      ..strokeWidth = 3;

    // Major arteries
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), roadPaint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65), roadPaint);
    canvas.drawLine(Offset(size.width * 0.4, 0), Offset(size.width * 0.4, size.height), roadPaint);
    canvas.drawLine(Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), roadPaint);

    // Diagonal bypass
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width * 0.85, 0), secondaryRoad);

    // Minor streets
    for (double y = 40; y < size.height; y += 70) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), secondaryRoad);
    }
    for (double x = 40; x < size.width; x += 70) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), secondaryRoad);
    }

    // Safety Patrol Zone Polygon
    final safeZonePaint = Paint()
      ..color = const Color(0x1A2FE0C9)
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
