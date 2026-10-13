import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_drawer.dart';
import '../theme/app_colors.dart';
import '../services/map_config.dart';

class ShareLocationPage extends StatefulWidget {
  const ShareLocationPage({super.key});

  @override
  State<ShareLocationPage> createState() => _ShareLocationPageState();
}

class _ShareLocationPageState extends State<ShareLocationPage> {
  bool _isLoading = false;
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  bool _isFallback = false;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoading = true);

    double? lat;
    double? lng;
    double? acc;
    bool fallback = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        fallback = true;
      } else {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          fallback = true;
        } else {
          Position? position;
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 5),
              ),
            ).timeout(const Duration(seconds: 5));
          } catch (_) {
            position = await Geolocator.getLastKnownPosition();
          }

          if (position != null) {
            lat = position.latitude;
            lng = position.longitude;
            acc = position.accuracy;
          } else {
            fallback = true;
          }
        }
      }
    } catch (_) {
      fallback = true;
    }

    if (lat == null || lng == null) {
      lat = SafeSphereMapConfig.defaultLatitude;
      lng = SafeSphereMapConfig.defaultLongitude;
      acc = 15.0;
      fallback = true;
    }

    if (mounted) {
      setState(() {
        _latitude = lat;
        _longitude = lng;
        _accuracy = acc;
        _isFallback = fallback;
        _lastUpdated = DateTime.now();
        _isLoading = false;
      });
    }
  }

  Future<void> _shareLocation() async {
    if (_latitude == null || _longitude == null) {
      await _fetchCurrentLocation();
    }

    final lat = _latitude ?? SafeSphereMapConfig.defaultLatitude;
    final lng = _longitude ?? SafeSphereMapConfig.defaultLongitude;
    final locationUrl = "https://www.google.com/maps?q=$lat,$lng";

    final message = _isFallback
        ? "🚨 [SafeSphere Alert] Location shared (GPS unavailable, using fallback coordinates):\n$locationUrl"
        : "🚨 [SafeSphere Live GPS Alert] I am sharing my live location for safety:\n$locationUrl";

    await Share.share(message);

    if (mounted && _isFallback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("GPS unavailable or permission denied. Default coordinates shared."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _openGoogleMaps() async {
    final lat = _latitude ?? SafeSphereMapConfig.defaultLatitude;
    final lng = _longitude ?? SafeSphereMapConfig.defaultLongitude;
    final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch Google Maps")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latStr = _latitude != null ? _latitude!.toStringAsFixed(5) : "Detecting...";
    final lngStr = _longitude != null ? _longitude!.toStringAsFixed(5) : "Detecting...";
    final accStr = _accuracy != null ? "±${_accuracy!.toStringAsFixed(1)}m" : "N/A";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Share Location"),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchCurrentLocation,
            tooltip: "Refresh GPS",
          )
        ],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📍 Location Status Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF101A33),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isFallback ? Colors.amber.withValues(alpha: 0.4) : AppColors.teal.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isFallback ? Icons.location_searching : Icons.gps_fixed,
                            color: _isFallback ? Colors.amber : AppColors.teal,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isFallback ? "GPS Fallback Mode" : "High-Accuracy GPS",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_isFallback ? Colors.amber : AppColors.teal).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isLoading ? "Acquiring..." : (_isFallback ? "Fallback" : "Active"),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isFallback ? Colors.amber : AppColors.teal,
                          ),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Latitude", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(latStr, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Longitude", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(lngStr, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Text("Accuracy: $accStr", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      if (_lastUpdated != null)
                        Text(
                          "Updated: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 🗺️ Simulated Map View Frame
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
                color: const Color(0xFF0D1526),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Vector Grid Canvas
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LocationGridPainter(),
                    ),
                  ),

                  // Radar Pulse / Pin
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.my_location, color: AppColors.teal, size: 28),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            "Live Coordinates Detected",
                            style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w600),
                          ),
                        )
                      ],
                    ),
                  ),

                  // Google Maps Tag
                  Positioned(
                    bottom: 8,
                    left: 12,
                    child: Row(
                      children: const [
                        Icon(Icons.map, color: Colors.white60, size: 14),
                        SizedBox(width: 4),
                        Text("Google Maps Ready", style: TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),

                  // Open in Maps Action
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14, color: AppColors.blue),
                      label: const Text("Open Map", style: TextStyle(fontSize: 11, color: AppColors.blue)),
                      onPressed: _openGoogleMaps,
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 🚀 Action Buttons
            ElevatedButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.share_location, color: Colors.black),
              label: const Text("Share My Live Location", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isLoading ? null : _shareLocation,
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.navigation, color: AppColors.blue),
              label: const Text("Open in Google Maps", style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.blue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _openGoogleMaps,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1A2FE0C9)
      ..strokeWidth = 1;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final circlePaint = Paint()
      ..color = const Color(0x1A2FE0C9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 40, circlePaint);
    canvas.drawCircle(center, 80, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
