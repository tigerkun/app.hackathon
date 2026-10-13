import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About")),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Icon(Icons.shield, size: 80, color: Colors.blue),
            const SizedBox(height: 16),

            const Text(
              "SafeSphere",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),

            const SizedBox(height: 12),
            const Text(
              "A smart personal safety platform designed to help users "
                  "stay safe, informed, and connected during emergencies.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),

            const SizedBox(height: 30),

            _feature(Icons.map, "Live Community Alerts"),
            _feature(Icons.smart_toy, "AI Safety Assistant"),
            _feature(Icons.share_location, "One-Tap Location Sharing"),
            _feature(Icons.warning_amber, "Emergency SOS"),

            const SizedBox(height: 30),

            const Divider(),

            const Text(
              "Built with privacy and security in mind. "
                  "Your data stays yours.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 20),
            const Text(
              "Version 1.0.0",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _feature(IconData icon, String text) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(text),
    );
  }
}
