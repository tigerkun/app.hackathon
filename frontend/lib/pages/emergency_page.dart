import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  String? _activeSosId;
  bool _isBroadcasting = false;
  int _monitorsCount = 0;
  int _escalationLevel = 0;
  int _ageSeconds = 0;
  Timer? _sosPollTimer;
  List<Map<String, dynamic>> _sosHistory = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    unawaited(AuthService.instance.processQueuedSosAlerts());
    _checkActiveSos();
    _loadSosHistory();
  }

  @override
  void dispose() {
    _sosPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveSos() async {
    final activeId = await AuthService.instance.getActiveSosId();
    if (activeId != null && activeId.isNotEmpty) {
      if (mounted) {
        setState(() {
          _activeSosId = activeId;
          _isBroadcasting = true;
        });
        _startSosPolling(activeId);
      }
    }
  }

  void _startSosPolling(String alertId) {
    _sosPollTimer?.cancel();
    _pollActiveSos(alertId);
    _sosPollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _pollActiveSos(alertId);
    });
  }

  void _stopSosPolling() {
    _sosPollTimer?.cancel();
    _sosPollTimer = null;
    AuthService.instance.clearActiveSos();
    if (mounted) {
      setState(() {
        _isBroadcasting = false;
        _activeSosId = null;
        _monitorsCount = 0;
        _escalationLevel = 0;
        _ageSeconds = 0;
      });
    }
  }

  Future<void> _pollActiveSos(String alertId) async {
    if (!mounted) return;
    try {
      final statusData = await AuthService.instance.fetchSosStatus(alertId);
      if (!mounted) return;
      if (statusData != null) {
        final status = statusData['status'] as String? ?? 'active';
        final monitorsRaw = statusData['monitorsConnected'] ?? statusData['wsClients'];
        final monitors = monitorsRaw is int ? monitorsRaw : (int.tryParse('$monitorsRaw') ?? 0);
        final escalationRaw = statusData['escalationLevel'];
        final escalation = escalationRaw is int ? escalationRaw : (int.tryParse('$escalationRaw') ?? 0);
        final ageSecRaw = statusData['ageSeconds'];
        final ageSec = ageSecRaw is int ? ageSecRaw : (int.tryParse('$ageSecRaw') ?? 0);

        if (status != 'active') {
          _stopSosPolling();
          _loadSosHistory();
        } else {
          setState(() {
            _monitorsCount = monitors;
            _escalationLevel = escalation;
            _ageSeconds = ageSec;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSosHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      final history = await AuthService.instance.fetchSosHistory(limit: 10);
      if (mounted) {
        setState(() {
          _sosHistory = history;
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

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

              // 📡 BROADCASTING STATUS BANNER (W2-3 / F3-1)
              if (_isBroadcasting) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radio_button_checked, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  "ACTIVE — broadcasting ${(_ageSeconds / 60).floor()}m",
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_escalationLevel > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "ESCALATED ×$_escalationLevel",
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _monitorsCount > 0
                                  ? "$_monitorsCount monitoring clients • Real-time GPS telemetry active • Tap I'm Safe Now to cease"
                                  : "Real-time GPS telemetry active • Tap I'm Safe Now to cease",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

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

              // 💬 SMS FALLBACK SOS
              _neutralCard(
                cardColor,
                Icons.sms_failed_outlined,
                "SMS Fallback SOS",
                "Open SMS composer prefilled with coordinates & contacts",
                textColor,
                subTextColor,
                () {
                  _triggerDirectSmsFallback(context);
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

              // 📜 SOS HISTORY (W2-3)
              Text(
                "SOS History",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Builder(
                builder: (context) {
                  final pastAlerts = _sosHistory
                      .where((a) => (a['status'] as String? ?? '').toLowerCase() != 'active')
                      .toList();

                  if (_isLoadingHistory) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  if (pastAlerts.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        "No past emergency alerts recorded.",
                        style: TextStyle(color: subTextColor, fontSize: 13),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final item in pastAlerts)
                        _sosHistoryCard(item, cardColor, textColor, subTextColor),
                    ],
                  );
                },
              ),

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
                    _stopSosPolling();
                    _loadSosHistory();
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

  Widget _sosHistoryCard(
    Map<String, dynamic> item,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final status = (item['status'] as String? ?? 'resolved').toUpperCase();
    final type = (item['alertType'] as String? ?? 'CRITICAL_SOS').replaceAll('_', ' ');
    final dateStr = item['triggeredAt'] as String? ?? item['createdAt'] as String? ?? '';
    String formattedTime = 'Past Alert';
    if (dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        formattedTime = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      } catch (_) {
        formattedTime = dateStr;
      }
    }

    final isResolved = status == 'RESOLVED';
    final badgeColor = isResolved ? Colors.green : Colors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(formattedTime, style: TextStyle(color: subTextColor, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

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
              await _startSosGraceCountdownAndDispatch(context);
            },
            child: const Text("Dispatch & Share"),
          ),
        ],
      ),
    );
  }

  Future<void> _startSosGraceCountdownAndDispatch(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SosCountdownDialog(durationSeconds: 5),
    );

    if (confirmed != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("SOS alert cancelled."),
            backgroundColor: Colors.grey,
          ),
        );
      }
      return;
    }

    // W2-6: Trigger tactile confirmation feedback
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    if (!context.mounted) return;
    await _executeSosDispatch(context);
  }

  Future<void> _executeSosDispatch(BuildContext context) async {
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
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

    // 2. Open native SMS composer prefilled with contacts and current location
    await _launchSmsFallback(authService, alertMsg);

    if (result != null) {
      final alertId = result['id'] as String? ?? (result['data']?['id'] as String?);
      if (alertId != null && alertId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _activeSosId = alertId;
            _isBroadcasting = true;
          });
          _startSosPolling(alertId);
        }
      }
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
  }

  Future<bool> _launchSmsFallback(AuthService authService, String alertMsg) async {
    try {
      final currentUser = authService.currentUser;
      final contactPhones = <String>[];
      if (currentUser?.emergencyContacts != null && currentUser!.emergencyContacts.isNotEmpty) {
        for (final c in currentUser.emergencyContacts) {
          final p = c.phone.trim();
          if (p.isNotEmpty && !contactPhones.contains(p)) {
            contactPhones.add(p);
          }
        }
      }
      if (contactPhones.isEmpty && currentUser?.emergencyContactPhone != null) {
        final p = currentUser!.emergencyContactPhone!.trim();
        if (p.isNotEmpty) contactPhones.add(p);
      }

      final recipients = contactPhones.isNotEmpty ? contactPhones.join(',') : '';
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: <String, String>{
          'body': alertMsg,
        },
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}

    // Fallback to generic share sheet if SMS composer cannot be launched
    try {
      await Share.share(alertMsg);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _triggerDirectSmsFallback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    double? lat;
    double? lng;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      lat = position.latitude;
      lng = position.longitude;
    } catch (_) {}

    final locationUrl = (lat != null && lng != null)
        ? "https://www.google.com/maps?q=$lat,$lng"
        : "GPS unavailable";
    final alertMsg = "🚨 [SafeSphere EMERGENCY ALERT] I need immediate help. My current live location is:\n$locationUrl";

    final launched = await _launchSmsFallback(AuthService.instance, alertMsg);
    if (!launched && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Could not open SMS composer")),
      );
    }
  }
}

class SosCountdownDialog extends StatefulWidget {
  final int durationSeconds;
  const SosCountdownDialog({super.key, this.durationSeconds = 5});

  @override
  State<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<SosCountdownDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining <= 1) {
        timer.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _remaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
          SizedBox(width: 8),
          Text("SOS Countdown", style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: _remaining / widget.durationSeconds,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                ),
              ),
              Text(
                "$_remaining",
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            "Dispatching SOS alert to responders and contacts in $_remaining seconds...",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            "Tap Cancel SOS immediately if triggered by accident.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _cancel,
            icon: const Icon(Icons.close),
            label: const Text("Cancel SOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
