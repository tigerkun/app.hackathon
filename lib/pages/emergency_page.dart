import 'package:flutter/material.dart';

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0B1220) : const Color(0xFFF4F6FA);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text("Emergency Info"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔴 TOP DISCLAIMER
              _InfoBanner(
                icon: Icons.shield_outlined,
                title: "Emergency Support & Safety Assistance",
                subtitle:
                    "This page helps you access help and inform trusted contacts. "
                    "It does not replace emergency services.",
                textColor: textColor,
                subTextColor: subTextColor,
              ),

              const SizedBox(height: 20),

              // 🚨 EMERGENCY CALL
              _ActionCard(
                color: const Color(0xFFB71C1C),
                icon: Icons.call,
                title: "Call Emergency",
                subtitle: "Dial 112 for immediate help",
                onTap: () {},
              ),

              const SizedBox(height: 20),

              // 📞 HELPLINES
              Text(
                "Emergency Helplines",
                style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              _HelplineCard(
                  color: cardColor,
                  textColor: textColor,
                  title: "National Emergency",
                  number: "112"),
              _HelplineCard(
                  color: cardColor,
                  textColor: textColor,
                  title: "Women Helpline",
                  number: "181"),
              _HelplineCard(
                  color: cardColor,
                  textColor: textColor,
                  title: "Ambulance",
                  number: "108"),
              _HelplineCard(
                  color: cardColor,
                  textColor: textColor,
                  title: "Fire Services",
                  number: "101"),

              const SizedBox(height: 24),

              // 🟠 INFORM CONTACTS
              _ActionCard(
                color: const Color(0xFFF9A825),
                icon: Icons.group,
                title: "Inform Trusted Contacts",
                subtitle:
                    "Send a manual alert with your last known location",
                onTap: () {
                  _showMessagePreview(context);
                },
              ),

              const SizedBox(height: 16),

              // 📍 SHARE LOCATION
              _NeutralCard(
                color: cardColor,
                icon: Icons.location_on,
                title: "Share My Current Location",
                subtitle: "One-time location sharing only",
                textColor: textColor,
                subTextColor: subTextColor,
                onTap: () {},
              ),

              const SizedBox(height: 24),

              // 🟡 SAFETY TIPS
              Text(
                "Emergency Guidance",
                style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              _TipCard(
                  color: cardColor,
                  textColor: textColor,
                  text: "Move to a crowded or well-lit area"),
              _TipCard(
                  color: cardColor,
                  textColor: textColor,
                  text: "Keep your phone battery sufficiently charged"),
              _TipCard(
                  color: cardColor,
                  textColor: textColor,
                  text: "Contact authorities if danger is immediate"),

              const SizedBox(height: 24),

              // 🟢 I'M SAFE
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.check_circle, color: Colors.green),
                label: const Text("I'm Safe Now"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 20),
                ),
              ),

              const SizedBox(height: 24),

              // ⚠️ BOTTOM DISCLAIMER
              Text(
                "SafeSphere does not provide emergency response services. "
                "For immediate danger, contact local authorities.",
                style: TextStyle(fontSize: 12, color: subTextColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessagePreview(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Send Alert Message"),
        content: const Text(
          "I may need help. Please try to contact me.\n"
          "Last known location: Your Area",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Share"),
          ),
        ],
      ),
    );
  }
}

// ---------------- OPTIMIZED WIDGET HELPERS ----------------

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subTextColor;

  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.orangeAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: subTextColor)),
            ],
          ),
        )
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _NeutralCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subTextColor;
  final VoidCallback onTap;

  const _NeutralCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.lightBlueAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(subtitle,
                      style: TextStyle(color: subTextColor, fontSize: 12)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _HelplineCard extends StatelessWidget {
  final Color color;
  final Color textColor;
  final String title;
  final String number;

  const _HelplineCard({
    required this.color,
    required this.textColor,
    required this.title,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: textColor)),
          Text(
            number,
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final Color color;
  final Color textColor;
  final String text;

  const _TipCard({
    required this.color,
    required this.textColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(color: textColor))),
        ],
      ),
    );
  }
}
