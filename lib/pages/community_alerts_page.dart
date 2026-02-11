import 'package:flutter/material.dart';

class CommunityAlertsPage extends StatefulWidget {
  const CommunityAlertsPage({super.key});

  @override
  State<CommunityAlertsPage> createState() => _CommunityAlertsPageState();
}

class _CommunityAlertsPageState extends State<CommunityAlertsPage> {
  String selectedFilter = 'All';
  bool locationDetected = false;

  final String detectedArea = "Your Area";

  final List<Map<String, dynamic>> alerts = [
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

      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              child: Text(
                "SafeSphere",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            _drawerItem(Icons.home, "Home", '/'),
            _drawerItem(Icons.report, "Report Near Me", '/report'),
            _drawerItem(Icons.campaign, "Community Alerts", '/community'),
            _drawerItem(Icons.chat, "Safety Assistant", '/chat'),
            _drawerItem(Icons.support_agent, "Emergency Info", '/emergency'),
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

            // Filter chips (UI only)
            Wrap(
              spacing: 10,
              children: ['All', 'Safety', 'Civic'].map((filter) {
                return ChoiceChip(
                  label: Text(filter),
                  selected: selectedFilter == filter,
                  onSelected: (_) {
                    setState(() => selectedFilter = filter);
                  },
                );
              }).toList(),
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
                  final alert = filteredAlerts[index];

                  return _alertCard(alert);
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

  Widget _alertCard(Map<String, dynamic> alert) {
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
                Icon(alert['icon'], color: alert['color']),
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alert['color'].withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    alert['type'],
                    style: TextStyle(
                        color: alert['color'],
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text(
                  alert['time'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              alert['message'],
              style: const TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 6),

            Text(
              "${alert['category']} • ${alert['area']}",
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 6),

            Text(
              alert['expiry'],
              style: const TextStyle(
                  fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  ListTile _drawerItem(IconData icon, String title, String route) {
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
