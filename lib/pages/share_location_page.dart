import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_drawer.dart';

class ShareLocationPage extends StatelessWidget {
  const ShareLocationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Share Location")),
      drawer: const AppDrawer(),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.share_location),
          label: const Text("Share My Live Location"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          onPressed: _shareLocation,
        ),
      ),
    );
  }

  void _shareLocation() {
    const latitude = 28.6139;
    const longitude = 77.2090;

    final locationUrl =
        "https://www.google.com/maps?q=$latitude,$longitude";

    Share.share(
      "🚨 I’m sharing my location for safety:\n$locationUrl",
    );
  }
}
