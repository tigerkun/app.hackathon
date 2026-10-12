import 'package:flutter/material.dart';

/// Simple marker model (lightweight & expandable)
class SafetyMarker {
  final Offset position; // relative (0–1 based)
  final IconData icon;
  final Color color;
  final String label;

  const SafetyMarker({
    required this.position,
    required this.icon,
    required this.color,
    required this.label,
  });
}

class MapPlaceholder extends StatelessWidget {
  final List<SafetyMarker> markers;

  const MapPlaceholder({
    super.key,
    required this.markers,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      children: [
        /// MAP BASE
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        /// GRID OVERLAY (realistic map feel)
        const CustomPaint(
          size: Size.infinite,
          painter: _GridPainter(),
        ),

        /// MARKERS
        // Optimization: Removed redundant .toList() in spread operator
        for (final marker in markers)
          Positioned(
            left: screenSize.width * marker.position.dx,
            top: screenSize.height * marker.position.dy,
            child: _MapMarker(marker: marker),
          ),
      ],
    );
  }
}

/// MARKER WIDGET
class _MapMarker extends StatelessWidget {
  final SafetyMarker marker;

  const _MapMarker({required this.marker});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: marker.color.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: marker.color.withValues(alpha: 0.4),
                blurRadius: 12,
              )
            ],
          ),
          child: Icon(
            marker.icon,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          marker.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        )
      ],
    );
  }
}

/// GRID PAINTER
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const gap = 60.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
