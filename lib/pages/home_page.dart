import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/app_drawer.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.location_on, size: 18),
            SizedBox(width: 6),
            Text("New Delhi"),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.purple,
        onPressed: () {
          Navigator.pushNamed(context, '/ai-assistant');
        },
        child: const Icon(Icons.smart_toy),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// 1️⃣ INTENT HEADLINE
          const Text(
            "How can we help you stay safe today?",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Real-time safety insights from your community",
            style: TextStyle(color: Colors.white60),
          ),

          const SizedBox(height: 20),

          /// 2️⃣ LOCAL SAFETY STATUS (ANCHOR CARD)
          const GlassContainer(
            borderColor: AppColors.teal,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.shield, size: 40, color: AppColors.teal),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Safety Level: Moderate",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Based on recent verified reports",
                          style: TextStyle(color: Colors.white60),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Last updated: 10 mins ago",
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          /// 3️⃣ PRIMARY ACTIONS
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.report,
                  title: "Report Near Me",
                  subtitle: "Submit a safety concern",
                  color: AppColors.amber,
                  onTap: () =>
                      Navigator.pushNamed(context, '/report'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.map,
                  title: "Safety Map",
                  subtitle: "View nearby alerts",
                  color: AppColors.blue,
                  onTap: () =>
                      Navigator.pushNamed(context, '/safety-map'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          /// 🤖 AI SAFETY RECOMMENDATIONS
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/ai-assistant'),
            child: GlassContainer(
              borderColor: AppColors.purple,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.smart_toy,
                        color: AppColors.purple,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "AI Safety Recommendations",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Personalized insights based on real-time activity",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),


          const SizedBox(height: 20),

          /// 4️⃣ RECENT LOCAL ACTIVITY
          const Text(
            "Recent Local Activity",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          const _ActivityItem(
            icon: Icons.lightbulb,
            text: "Poor street lighting reported",
            time: "30 mins ago",
          ),
          const _ActivityItem(
            icon: Icons.visibility,
            text: "Suspicious activity flagged",
            time: "1 hr ago",
          ),

          const SizedBox(height: 16),

          /// 5️⃣ COMMUNITY ALERTS PREVIEW
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/alerts'),
            child: GlassContainer(
              borderColor: AppColors.red,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active,
                          color: AppColors.red),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Community Alerts",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "3 new verified alerts near your area",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "3",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),


          const SizedBox(height: 16),

          /// 6️⃣ SAFETY TIP
          const GlassContainer(
            borderColor: AppColors.teal,
            child: ListTile(
              leading: Icon(Icons.info, color: AppColors.teal),
              title: Text(
                "Prefer well-lit routes while traveling at night",
              ),
            ),
          ),

          const SizedBox(height: 16),

          /// 7️⃣ EMERGENCY STRIP
          const Center(
            child: Text(
              "For immediate danger, contact emergency services.",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SMALL HELPERS
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderColor: color,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(text),
      trailing: Text(
        time,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}
