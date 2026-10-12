import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';

class SafetyMapPage extends StatelessWidget {
  const SafetyMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text("Safety Map"),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),

      body: Stack(
        children: [

          /// ---------------- MAP CANVAS ----------------
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey.shade200,
            child: const CustomPaint(
              painter: _GridPainter(),
            ),
          ),

          /// User location
          const Positioned(
            top: 220,
            left: 180,
            child: _MapMarker(
              color: Colors.blue,
              label: "You",
            ),
          ),

          /// Mock alert markers
          const Positioned(
            top: 160,
            left: 120,
            child: _MapMarker(
              color: Colors.red,
              label: "Warning",
            ),
          ),

          const Positioned(
            top: 300,
            left: 90,
            child: _MapMarker(
              color: Colors.orange,
              label: "Caution",
            ),
          ),

          const Positioned(
            top: 260,
            left: 260,
            child: _MapMarker(
              color: Colors.green,
              label: "Info",
            ),
          ),

          /// ---------------- FILTER CHIPS ----------------
          const Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _MapChip("All"),
                  _MapChip("Safety"),
                  _MapChip("Civic"),
                  _MapChip("Lighting"),
                  _MapChip("Suspicious"),
                ],
              ),
            ),
          ),

          /// ---------------- ALERT PREVIEW ----------------
          const Positioned(
            left: 12,
            right: 12,
            bottom: 110,
            child: _AlertPreviewCard(),
          ),

          /// ---------------- LEGEND ----------------
          const Positioned(
            right: 12,
            bottom: 12,
            child: _LegendCard(),
          ),

          /// ---------------- REPORT BUTTON ----------------
          Positioned(
            right: 20,
            bottom: 200,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(context, '/report'),
              icon: const Icon(Icons.flag),
              label: const Text("Report Near This Location"),
            ),
          ),

          /// ---------------- FOOTER ----------------
          const Positioned(
            left: 12,
            right: 12,
            bottom: 4,
            child: Text(
              "For immediate danger, contact emergency services.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===================================================
/// GRID BACKGROUND (FAKE MAP)
/// ===================================================
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ===================================================
/// MAP MARKER
/// ===================================================
class _MapMarker extends StatelessWidget {
  final Color color;
  final String label;

  const _MapMarker({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_pin, color: color, size: 36),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

/// ===================================================
/// FILTER CHIP
/// ===================================================
class _MapChip extends StatelessWidget {
  final String text;

  const _MapChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(text),
        backgroundColor: Colors.white,
      ),
    );
  }
}

/// ===================================================
/// ALERT PREVIEW CARD
/// ===================================================
class _AlertPreviewCard extends StatelessWidget {
  const _AlertPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: ListTile(
        leading: const Icon(Icons.warning, color: Colors.red),
        title: const Text("Suspicious Activity"),
        subtitle: const Text("Reported near Main Street • 10 mins ago"),
        trailing: TextButton(
          onPressed: () => Navigator.pushNamed(context, '/alerts'),
          child: const Text("View"),
        ),
      ),
    );
  }
}

/// ===================================================
/// LEGEND CARD
/// ===================================================
class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Legend", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            _LegendRow(Colors.green, "Info"),
            _LegendRow(Colors.orange, "Caution"),
            _LegendRow(Colors.red, "Warning"),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendRow(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_pin, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
