import 'package:flutter/material.dart';

class AssistantHome extends StatelessWidget {
  const AssistantHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1220),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // 🟦 FRIENDLY INTRO
          const _SoftCard(
            icon: Icons.shield,
            iconColor: Color(0xFF38BDF8),
            title: "You're not alone",
            subtitle:
                "I’m here to help you stay calm, aware, and safe — step by step.",
          ),

          const SizedBox(height: 18),

          // 🧠 SAFETY ASSISTANT
          _actionCard(
            context,
            icon: Icons.smart_toy,
            color: const Color(0xFF38BDF8),
            title: "Safety Assistant",
            subtitle: "Calm help for uncertain situations",
            route: '/assistant-chat',
          ),

          // 🛣️ SAFE ROUTE
          _actionCard(
            context,
            icon: Icons.route,
            color: const Color(0xFF2DD4BF),
            title: "Safe Route Planner",
            subtitle: "Prefer safer, well-lit areas",
            route: '/safe-route',
          ),

          // 📍 SHARE LOCATION
          _actionCard(
            context,
            icon: Icons.location_on,
            color: const Color(0xFFFBBF24),
            title: "Share My Location",
            subtitle: "One-time manual sharing",
            route: '/share',
          ),

          const SizedBox(height: 12),

          // 🟢 I'M SAFE
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.check_circle,
                color: Color(0xFF4ADE80)),
            label: const Text(
              "I’m Safe Now",
              style: TextStyle(color: Color(0xFF4ADE80)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF4ADE80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          const SizedBox(height: 20),

          // 🚨 EMERGENCY
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.call, color: Colors.white, size: 34),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "Call Emergency (112)",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ⚠️ DISCLAIMER
          const Text(
            "SafeSphere does not provide emergency response services.\n"
                "For immediate danger, contact local authorities.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
      BuildContext context, {
        required IconData icon,
        required Color color,
        required String title,
        required String subtitle,
        required String route,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, size: 30, color: color),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600)),
        subtitle:
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _SoftCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 36, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
