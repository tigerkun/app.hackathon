import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';



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
              _infoBanner(
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
              _actionCard(
                color: const Color(0xFFB71C1C),
                icon: Icons.call,
                title: "Call Emergency",
                subtitle: "Dial 112 for immediate help",
                onTap: () => _makeCall(context, "112"),
              ),

              const SizedBox(height: 20),

              // 📞 HELPLINES
              Text("Emergency Helplines",
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor, fontWeight: FontWeight.bold)),

              const SizedBox(height: 12),

              _helplineCard(context, cardColor, textColor, "National Emergency", "112"),
              _helplineCard(context, cardColor, textColor, "Women Helpline", "181"),
              _helplineCard(context, cardColor, textColor, "Ambulance", "108"),
              _helplineCard(context, cardColor, textColor, "Fire Services", "101"),

              const SizedBox(height: 24),

              // 🟠 INFORM CONTACTS
              _actionCard(
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
              _neutralCard(
                cardColor,
                Icons.location_on,
                "Share My Current Location",
                "One-time location sharing only",
                textColor,
                subTextColor,
                () {
                  Navigator.pushNamed(context, '/share');
                },
              ),

              const SizedBox(height: 24),

              // 🟡 SAFETY TIPS
              Text("Emergency Guidance",
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor, fontWeight: FontWeight.bold)),

              const SizedBox(height: 12),

              _tipCard(cardColor, textColor, "Move to a crowded or well-lit area"),
              _tipCard(cardColor, textColor,
                  "Keep your phone battery sufficiently charged"),
              _tipCard(cardColor, textColor,
                  "Contact authorities if danger is immediate"),

              const SizedBox(height: 24),

              // 🟢 I'M SAFE
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final authService = AuthService.instance;
                  final activeSosId = await authService.getActiveSosId();

                  if (activeSosId == null || activeSosId.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text("No active emergency SOS session to resolve."),
                      ),
                    );
                    return;
                  }

                  final success = await authService.resolveSos(
                    alertId: activeSosId,
                    notes: 'Resolved by user directly in Emergency screen',
                  );

                  if (success) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text("Active SOS alert marked resolved and broadcast updated."),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text("Could not resolve SOS alert with server. Please check connection."),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
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

  // ---------------- HELPERS ----------------

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.orangeAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: subTextColor)),
            ],
          ),
        )
      ],
    );
  }

  Widget _actionCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
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

  Widget _neutralCard(
      Color color,
      IconData icon,
      String title,
      String subtitle,
      Color textColor,
      Color subTextColor,
      VoidCallback onTap,
      ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                  Text(title,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold)),
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

  Widget _helplineCard(
      BuildContext context, Color color, Color textColor, String title, String number) {
    return GestureDetector(
      onTap: () => _makeCall(context, number),
      behavior: HitTestBehavior.opaque,
      child: Container(
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
            Text(number,
                style: TextStyle(
                    color: textColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _makeCall(BuildContext context, String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open dialer for $phoneNumber')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error dialing $phoneNumber: $e')),
        );
      }
    }
  }

  Widget _tipCard(Color color, Color textColor, String text) {
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

  void _showMessagePreview(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Send Alert Message"),
        content: const Text(
          "This will dispatch a real-time SOS broadcast with your verified device GPS coordinates and open SMS/Share to notify your contacts.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);

              double? lat;
              double? lng;
              double? acc;

              try {
                LocationPermission permission = await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();
                }

                if (permission == LocationPermission.whileInUse ||
                    permission == LocationPermission.always) {
                  final position = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 5),
                  );
                  lat = position.latitude;
                  lng = position.longitude;
                  acc = position.accuracy;
                }
              } catch (_) {}

              if (lat == null || lng == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Cannot dispatch SOS without GPS fix. Please enable device location."),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              // 1. Dispatch real HTTP POST /api/v1/sos/trigger to SafeSphere backend
              final authService = AuthService.instance;
              final result = await authService.triggerSos(
                latitude: lat,
                longitude: lng,
                accuracy: acc,
                alertType: 'CRITICAL_SOS',
                notes: 'Manual alert triggered from Emergency screen',
              );

              final locationUrl = "https://www.google.com/maps?q=$lat,$lng";
              final alertMsg = "🚨 [SafeSphere EMERGENCY ALERT] I need immediate help. My current live location is:\n$locationUrl";

              // 2. Open native SMS / messaging share intent
              await Share.share(alertMsg);

              if (result != null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Emergency SOS broadcast to monitoring channel and shared."),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Location shared via SMS (Backend broadcast offline)."),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text("Dispatch & Share"),
          ),
        ],
      ),
    );
  }
}
