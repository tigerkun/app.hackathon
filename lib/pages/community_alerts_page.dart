import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';

class CommunityAlertsPage extends StatefulWidget {
  const CommunityAlertsPage({super.key});

  @override
  State<CommunityAlertsPage> createState() => _CommunityAlertsPageState();
}

class _CommunityAlertsPageState extends State<CommunityAlertsPage> {
  String selectedFilter = 'All';
  bool locationDetected = false;

  final String detectedArea = "Your Area";

  static const List<Map<String, dynamic>> alerts = [
    {
      'id': '1',
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
      'id': '2',
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
      'id': '3',
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
        content: Text("Showing community alerts near $detectedArea."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _selectFilter(String filter) {
    setState(() {
      selectedFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredAlerts = selectedFilter == 'All'
        ? alerts
        : alerts
            .where((alert) => alert['domain'] == selectedFilter)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Community Alerts"),
      ),

      drawer: const AppDrawer(),

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
                  key: ValueKey('chip_$filter'),
                  label: Text(filter),
                  selected: selectedFilter == filter,
                  onSelected: (_) => _selectFilter(filter),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Alerts list OR empty state
            Expanded(
              child: filteredAlerts.isEmpty
                  ? const Center(
                      child: Text(
                        "No active community alerts in your area.",
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredAlerts.length,
                      itemBuilder: (context, index) {
                        final alert = filteredAlerts[index];
                        return _AlertCard(
                          key: ValueKey(alert['id']),
                          alert: alert,
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
