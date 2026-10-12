import 'package:flutter/material.dart';

class CommunityAlertsPage extends StatefulWidget {
  const CommunityAlertsPage({super.key});

  @override
  State<CommunityAlertsPage> createState() => _CommunityAlertsPageState();
}

class _CommunityAlertsPageState extends State<CommunityAlertsPage> {
  String selectedFilter = 'All';
  bool locationDetected = false;

  static const String detectedArea = "Your Area";

  static const List<Map<String, dynamic>> alerts = [
    {
      'type': 'Warning',
      'domain': 'Safety',
      'category': 'Suspicious Activity',
      'icon': Icons.warning_amber,
      'message': 'Multiple people reported suspicious movement at night.',
      'area': 'Main Road',
      'time': '15 mins ago',
      'expiry': 'Expires in 2 hours',
      'color': Colors.redAccent,
    },
    {
      'type': 'Caution',
      'domain': 'Civic',
      'category': 'Poor Lighting',
      'icon': Icons.lightbulb_outline,
      'message': 'Street lights not functioning in this area.',
      'area': 'Bus Stop Zone',
      'time': '40 mins ago',
      'expiry': 'Valid till tonight',
      'color': Colors.orangeAccent,
    },
    {
      'type': 'Info',
      'domain': 'Civic',
      'category': 'Road Hazard',
      'icon': Icons.traffic,
      'message': 'Road repair work causing partial blockage.',
      'area': 'Market Street',
      'time': '1 hr ago',
      'expiry': 'Expires tomorrow',
      'color': Colors.green,
    },
  ];

  @override
  void initState() {
    super.initState();

    // Mock location detection delay
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        locationDetected = true;
      });

      _showLocationPopup();
    });
  }

  void _showLocationPopup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Location Detected"),
        content: const Text("Showing community alerts near $detectedArea."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredAlerts = selectedFilter == 'All'
        ? alerts
        : alerts
            .where((alert) => alert['domain'] == selectedFilter)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Community Alerts"),
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: const [
            DrawerHeader(
              child: Text(
                "SafeSphere",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            _DrawerItem(icon: Icons.home, title: "Home", route: '/'),
            _DrawerItem(icon: Icons.report, title: "Report Near Me", route: '/report'),
            _DrawerItem(icon: Icons.campaign, title: "Community Alerts", route: '/community'),
            _DrawerItem(icon: Icons.chat, title: "Safety Assistant", route: '/chat'),
            _DrawerItem(icon: Icons.support_agent, title: "Emergency Info", route: '/emergency'),
          ],
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location label
            Text(
              locationDetected
                  ? "Alerts near $detectedArea"
                  : "Detecting your location…",
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Filter chips
            Wrap(
              spacing: 10,
              children: ['All', 'Safety', 'Civic'].map((filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: selectedFilter == filter,
                  onSelected: (_) {
                    if (selectedFilter != filter) {
                      setState(() => selectedFilter = filter);
                    }
                  },
                );
              }).toList(growable: false),
            ),

            const SizedBox(height: 16),

            // Alerts list OR empty state
            Expanded(
              child: alerts.isEmpty
                  ? const Center(
                      child: Text(
                        "No active community alerts in your area.",
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredAlerts.length,
                      itemBuilder: (context, index) {
                        return _AlertCard(
                          key: ValueKey(filteredAlerts[index]['message']),
                          alert: filteredAlerts[index],
                        );
                      },
                    ),
            ),

            const SizedBox(height: 8),

            // Disclaimer
            const Text(
              "Community alerts are informational and do not replace emergency services.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted StatelessWidget for Alert Card to prevent rebuilding subtree
class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;

  const _AlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final Color color = alert['color'] as Color;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + priority
            Row(
              children: [
                Icon(alert['icon'] as IconData, color: color),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    alert['type'] as String,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text(
                  alert['time'] as String,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              alert['message'] as String,
              style: const TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 6),

            Text(
              "${alert['category']} • ${alert['area']}",
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 6),

            Text(
              alert['expiry'] as String,
              style: const TextStyle(
                  fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted DrawerItem widget
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String route;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }
}
