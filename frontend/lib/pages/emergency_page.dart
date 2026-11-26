// F5-1: Hardware panic gestures (volume-down long-press ~1.5s via volume_controller and shake-to-SOS
// via sensors_plus) with honest gating, intermediate confirmation, and mandatory 5s countdown dialog.
// Real hardware interception degrades gracefully if platform channels are unsupported.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/gesture_service.dart';
import '../services/map_config.dart';
import '../data/auth_state.dart';
import '../theme/app_colors.dart';

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
  int _contactsNotified = 0;
  Timer? _sosPollTimer;
  List<Map<String, dynamic>> _sosHistory = [];
  bool _isLoadingHistory = false;

  // Two-way SOS responder chat (F4-1)
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _chatMessages = [];
  bool _isSendingChat = false;
  WebSocket? _chatWs;
  bool _isWsConnected = false;
  Timer? _chatPollTimer;
  String? _resolveToken;
  // Incremented on every connect attempt/teardown — stale sockets from a
  // previous generation must never overwrite _chatWs or drive UI state.
  int _chatWsGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(AuthService.instance.processQueuedSosAlerts());
    _checkActiveSos();
    _loadSosHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GestureService.instance.startListening(
          context,
          onSosConfirmed: () async {
            if (mounted) {
              await _executeSosDispatch(context);
            }
          },
        );
      }
    });
  }

  @override
  void dispose() {
    GestureService.instance.stopListening();
    _sosPollTimer?.cancel();
    _teardownChat(updateUi: false);
    _chatController.dispose();
    _chatScrollController.dispose();
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
    _initChat(alertId);
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
    _teardownChat();
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

  Future<void> _initChat(String alertId) async {
    _resolveToken = await AuthService.instance.getSosResolveToken(alertId);
    await _loadChatMessages(alertId);
    unawaited(_connectChatWs(alertId));
  }

  void _teardownChat({bool updateUi = true}) {
    _chatWsGeneration++;
    _chatPollTimer?.cancel();
    _chatPollTimer = null;
    try {
      _chatWs?.close();
    } catch (_) {}
    _chatWs = null;
    if (updateUi && mounted) {
      setState(() {
        _isWsConnected = false;
        _chatMessages = [];
      });
    }
  }

  Future<void> _connectChatWs(String alertId) async {
    final generation = ++_chatWsGeneration;
    try {
      _chatWs?.close();
      final base = AuthService.instance.baseUrl;
      final wsBase = base.startsWith('https://')
          ? base.replaceFirst('https://', 'wss://')
          : base.replaceFirst('http://', 'ws://');
      final wsUrl = '$wsBase/ws/sos';

      final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
      // M6 dispose-race guard: if the emergency page was disposed while the
      // socket connected, close it immediately rather than leak a listener.
      if (!mounted || generation != _chatWsGeneration) {
        await ws.close().catchError((_) {});
        return;
      }
      _chatWs = ws;
      if (mounted) setState(() => _isWsConnected = true);

      // Subscribe to this alert room so backend routes alert frames directly to this socket
      final token = _resolveToken ?? await AuthService.instance.storage.getString(AuthService.keyToken);
      try {
        ws.add(jsonEncode({
          'type': 'SUBSCRIBE_ALERT',
          'alertId': alertId,
          'token': token,
        }));
      } catch (_) {}

      ws.listen(
        (event) {
          try {
            final data = jsonDecode(event as String);
            if (data is Map<String, dynamic> && data['type'] == 'CHAT_MESSAGE') {
              if (data['alertId'] == alertId && data['message'] is Map) {
                final newMsg = Map<String, dynamic>.from(data['message'] as Map);
                if (mounted) {
                  setState(() {
                    if (!_chatMessages.any((m) => m['id'] == newMsg['id'])) {
                      _chatMessages.add(newMsg);
                    }
                  });
                  _scrollChatToBottom();
                }
              }
            }
          } catch (_) {}
        },
        onDone: () {
          if (generation != _chatWsGeneration) return;
          if (mounted) setState(() => _isWsConnected = false);
          _startChatFallbackPolling(alertId);
        },
        onError: (_) {
          if (generation != _chatWsGeneration) return;
          if (mounted) setState(() => _isWsConnected = false);
          _startChatFallbackPolling(alertId);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isWsConnected = false);
      _startChatFallbackPolling(alertId);
    }
  }

  void _startChatFallbackPolling(String alertId) {
    if (_chatPollTimer != null && _chatPollTimer!.isActive) return;
    _chatPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _isWsConnected) {
        if (_isWsConnected) _chatPollTimer?.cancel();
        return;
      }
      await _loadChatMessages(alertId);
    });
  }

  Future<void> _loadChatMessages(String alertId) async {
    try {
      final token = _resolveToken ?? await AuthService.instance.storage.getString(AuthService.keyToken);
      final messages = await AuthService.instance.fetchSosMessages(alertId, token: token);
      if (mounted) {
        setState(() {
          _chatMessages = messages;
        });
        _scrollChatToBottom();
      }
    } catch (_) {}
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatRelativeTime(dynamic isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _activeSosId == null || _isSendingChat) return;

    if (text.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message too long (max 500 characters)')),
      );
      return;
    }

    setState(() => _isSendingChat = true);
    _chatController.clear();

    final alertId = _activeSosId!;
    final token = _resolveToken ?? await AuthService.instance.storage.getString(AuthService.keyToken);
    bool sentViaWs = false;

    if (_chatWs != null && _chatWs!.readyState == WebSocket.open) {
      try {
        final frame = jsonEncode({
          'type': 'CHAT_MESSAGE',
          'alertId': alertId,
          'token': token,
          'text': text,
        });
        _chatWs!.add(frame);
        sentViaWs = true;
      } catch (_) {
        sentViaWs = false;
      }
    }

    if (!sentViaWs) {
      try {
        final res = await AuthService.instance.sendSosMessage(alertId, text, token: token);
        if (res != null && mounted) {
          setState(() {
            if (!_chatMessages.any((m) => m['id'] == res['id'])) {
              _chatMessages.add(res);
            }
          });
          _scrollChatToBottom();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: $e')),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isSendingChat = false);
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
        final notifiedRaw = statusData['emergencyContactsNotified'];
        final notified = notifiedRaw is int ? notifiedRaw : (int.tryParse('$notifiedRaw') ?? 0);

        if (status != 'active') {
          _stopSosPolling();
          _loadSosHistory();
        } else {
          setState(() {
            _monitorsCount = monitors;
            _escalationLevel = escalation;
            _ageSeconds = ageSec;
            _contactsNotified = notified;
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

              // 🆘 POST-DISPATCH REASSURANCE HERO (M1.3): plain-language,
              // jargon-free. A person in distress reads reassurance, not
              // engineering status words.
              if (_isBroadcasting) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "HELP IS ON THE WAY",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Your SOS is active. Stay on this screen.",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            "Help requested ${(_ageSeconds / 60).floor()} min ${_ageSeconds % 60} sec ago",
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                      if (_escalationLevel > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "Alerted again — still waiting for help",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        _monitorsCount > 0
                            ? "$_monitorsCount ${_monitorsCount == 1 ? 'person is' : 'people are'} watching your location live"
                            : "Your emergency contacts can see your location live",
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      // M5: WhatsApp-first share — one tap pulls a fresh GPS
                      // fix and opens WhatsApp with a help message + location
                      // link (falls back to the system share sheet).
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.chat, size: 20, color: Colors.white),
                              label: const Text(
                                "Share via WhatsApp",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _shareSosViaWhatsApp,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            width: 48,
                            child: IconButton.filledTonal(
                              icon: const Icon(Icons.share, size: 20, color: Colors.white),
                              tooltip: "Share with any app",
                              onPressed: _shareSosViaWhatsApp,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Stand-down must be reachable at the TOP of the active
                      // SOS view — a victim who is safe should never have to
                      // scroll past history to end the alert.
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _resolveActiveSos,
                          icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          label: const Text(
                            "I'm Safe — Stop This Alert",
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 💬 TWO-WAY SOS RESPONDER CHAT (F4-1)
              if (_isBroadcasting && _activeSosId != null) ...[
                _buildResponderChatPanel(textColor, cardColor, isDark),
              ],

              // F5-3: Discreet mode fake-call screen affordance
              if (AuthState().isDiscreetMode) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_off, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Discreet Mode active: SOS buttons visually muted. UI-level discretion only.",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                _actionCard(
                  color: const Color(0xFF0F766E),
                  icon: Icons.phone_callback,
                  title: "Fake Call Screen",
                  subtitle: "Simulate an incoming phone call to exit uncomfortable situations",
                  semanticsLabel: "Fake call screen",
                  onTap: () => _showFakeCallScreen(context),
                ),
                const SizedBox(height: 16),
              ],

              // 🚨 EMERGENCY CALL
              _actionCard(
                color: AuthState().isDiscreetMode ? const Color(0xFF1E293B) : const Color(0xFFB71C1C),
                icon: Icons.call,
                title: "Call Emergency",
                subtitle: "Dial 112 for immediate help",
                semanticsLabel: "Call 112",
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
                color: AuthState().isDiscreetMode ? const Color(0xFF334155) : const Color(0xFFB45309),
                icon: Icons.group,
                title: "Inform Trusted Contacts",
                subtitle:
                    "Send a manual alert with your last known location",
                semanticsLabel: "Trigger emergency SOS",
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
                semanticsLabel: "Send emergency SMS fallback",
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
                semanticsLabel: "Share my current live location",
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
                  onPressed: _resolveActiveSos,
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  label: const Text("I'm Safe Now"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    minimumSize: const Size(double.infinity, 64),
                    padding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 20),
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


  /// Shared resolve flow: used by the bottom "I'm Safe Now" button, the
  /// broadcast hero, and the "False alarm" quick reply.
  Future<void> _resolveActiveSos() async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
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
      // M1.4: "I'm Safe" confirmation — show exactly who was
      // notified, honestly accounting for channels that are
      // not configured yet (no fabricated delivery claims).
      if (mounted) {
        final contacts =
            AuthService.instance.currentUser?.emergencyContacts ??
            const [];
        final names = contacts
            .map((c) => c.name)
            .where((n) => n.isNotEmpty)
            .toList();
        final contactLine = names.isEmpty
            ? "Your emergency contacts"
            : names.join(", ");
        final channelLine = _contactsNotified > 0
            ? "$_contactsNotified notification(s) were delivered to them."
            : "SMS/email alerts activate when a delivery gateway is configured — your live monitoring clients were notified.";
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.verified, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text("You're Safe",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "✓ Your SOS was resolved and everyone watching was updated.",
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  "Notified: $contactLine",
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  channelLine,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Done"),
              ),
            ],
          ),
        );
      }
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Could not resolve SOS alert with server. Please check connection."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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
    String? semanticsLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? title,
      child: GestureDetector(
        onTap: () {
          try {
            HapticFeedback.lightImpact();
          } catch (_) {}
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
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
    VoidCallback onTap, {
    String? semanticsLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? title,
      child: GestureDetector(
        onTap: () {
          try {
            HapticFeedback.lightImpact();
          } catch (_) {}
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
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
      ),
    );
  }

  Widget _helplineCard(
      BuildContext context, Color color, Color textColor, String title, String number) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _makeCall(context, number),
      child: Semantics(
        button: true,
        label: "Call $title $number",
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                number,
                style: TextStyle(
                    color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _makeCall(BuildContext context, String phoneNumber) async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
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
            SnackBar(
              content: Text('Could not open dialer for $phoneNumber'),
              action: SnackBarAction(
                label: 'Options',
                textColor: AppColors.teal,
                onPressed: () => _showDialerFallback(context, phoneNumber),
              ),
            ),
          );
          _showDialerFallback(context, phoneNumber);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error dialing $phoneNumber: $e'),
            action: SnackBarAction(
              label: 'Options',
              textColor: AppColors.teal,
              onPressed: () => _showDialerFallback(context, phoneNumber),
            ),
          ),
        );
        _showDialerFallback(context, phoneNumber);
      }
    }
  }

  /// Fallback sheet when tel: cannot be launched (e.g. tablet, wifi device, no SIM)
  void _showDialerFallback(BuildContext context, String phoneNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101A33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_disabled, color: AppColors.red, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Cannot open phone dialer",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "No dialer or SIM available for $phoneNumber",
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Emergency Helpline",
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        Text(
                          phoneNumber,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text("Copy", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: phoneNumber));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Copied $phoneNumber to clipboard")),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  side: const BorderSide(color: AppColors.teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.share_location, size: 18),
                label: const Text(
                  "Share My Location with Contacts",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _shareSosViaWhatsApp();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponderChatPanel(Color textColor, Color cardColor, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isWsConnected ? Colors.teal.withValues(alpha: 0.5) : Colors.orangeAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.forum, color: Colors.tealAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Two-Way Responder Chat",
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isWsConnected ? Colors.teal.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isWsConnected ? Colors.teal : Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isWsConnected ? Colors.tealAccent : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isWsConnected ? "WS Live" : "REST Poll (5s)",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _isWsConnected ? Colors.tealAccent : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 180,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _chatMessages.isEmpty
                ? Center(
                    child: Text(
                      "No messages yet.\nType below to update emergency responders or clarify your situation.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _chatMessages[index];
                      final isVictim = msg['senderRole'] == 'victim';
                      final text = msg['text']?.toString() ?? '';
                      final roleLabel = isVictim ? "You (Victim)" : "Emergency Responder";
                      final timeStr = msg['createdAt'] != null
                          ? _formatRelativeTime(msg['createdAt'])
                          : '';

                      return Align(
                        alignment: isVictim ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: isVictim
                                ? (isDark ? const Color(0xFF0F766E) : const Color(0xFF0D9488))
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(isVictim ? 12 : 2),
                              bottomRight: Radius.circular(isVictim ? 2 : 12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                isVictim ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    roleLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isVictim ? Colors.tealAccent : Colors.amberAccent,
                                    ),
                                  ),
                                  if (timeStr.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                text,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isVictim ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          // M1.8: one-tap quick replies — each sends a real CHAT_MESSAGE
          // through the same delivery path (server rate limits still apply).
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final reply in const [
                    "I'm OK",
                    "Call 112",
                    "Come get me",
                    "False alarm — I'm safe"
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(reply, style: const TextStyle(fontSize: 11)),
                        backgroundColor:
                            isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        side: BorderSide(
                            color: Colors.tealAccent.withValues(alpha: 0.4)),
                        onPressed: _isSendingChat || _activeSosId == null
                            ? null
                            : () {
                                _chatController.text = reply;
                                _sendChatMessage();
                                // "False alarm — I'm safe" is a stand-down
                                // intent, not just a chat message: offer the
                                // same resolve flow as the I'm Safe button.
                                if (reply == "False alarm — I'm safe") {
                                  _resolveActiveSos();
                                }
                              },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    maxLength: 500,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Tell responders: 'Urgent', 'Safe'...",
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                      counterText: "",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.tealAccent),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                _isSendingChat
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.tealAccent, size: 22),
                        onPressed: _sendChatMessage,
                        tooltip: "Send message",
                      ),
              ],
            ),
          ),
        ],
      ),
    );
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

  void _showFakeCallScreen(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      pageBuilder: (ctx, anim1, anim2) {
        return const FakeCallOverlay();
      },
    );
  }

  void _showMessagePreview(BuildContext context) {
    // F4-2-alt: The 5-second countdown dialog is the ONLY gate — no redundant confirmation prompts.
    _startSosGraceCountdownAndDispatch(context);
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

  /// Resolves live GPS coordinates, falling back to last-known GPS or
  /// LocationService's active location so an emergency alert is never blocked.
  Future<({double? lat, double? lng, double? acc})> _resolveEmergencyCoordinates({
    bool requestPermission = false,
  }) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
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
        return (
          lat: position.latitude,
          lng: position.longitude,
          acc: position.accuracy,
        );
      }
    } catch (_) {}

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (lat: last.latitude, lng: last.longitude, acc: last.accuracy);
      }
    } catch (_) {}

    final loc = LocationService.instance;
    if (loc.hasLiveGps || loc.isManualOverride) {
      return (lat: loc.currentLat, lng: loc.currentLng, acc: null);
    }
    return (lat: null, lng: null, acc: null);
  }

  Future<void> _executeSosDispatch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final coords = await _resolveEmergencyCoordinates(requestPermission: true);
    final double? lat = coords.lat;
    final double? lng = coords.lng;
    final double? acc = coords.acc;

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

    // F5-2: Short audio cue and heavy tactile impact on SOS dispatch
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

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

  /// M5: WhatsApp-first SOS share. Pulls a FRESH GPS fix (never reuses a
  /// stale trigger coordinate silently — on GPS failure it still opens the
  /// composer without coordinates rather than faking them), builds a help
  /// message with a maps deep link, and opens WhatsApp via the universal
  /// wa.me scheme. If WhatsApp is unavailable it falls back to the system
  /// share sheet so the message always has a way out.
  Future<void> _shareSosViaWhatsApp() async {
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
    } catch (_) {
      final fallback = await _resolveEmergencyCoordinates();
      lat = fallback.lat;
      lng = fallback.lng;
    }

    final buffer = StringBuffer();
    buffer.write("🚨 [SafeSphere EMERGENCY] I need help RIGHT NOW.");
    if (_ageSeconds > 0) {
      buffer.write(" SOS active ${(_ageSeconds / 60).floor()} min.");
    }
    if (lat != null && lng != null) {
      buffer.write("\n📍 My live location: https://www.google.com/maps?q=$lat,$lng");
    } else {
      buffer.write("\n📍 (Could not get GPS fix — call me, do not assume my location.)");
    }

    final uri = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}");
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    // WhatsApp/web unavailable → system share sheet (honest fallback).
    try {
      await Share.share(buffer.toString());
    } catch (_) {}
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
    final coords = await _resolveEmergencyCoordinates();
    final double? lat = coords.lat;
    final double? lng = coords.lng;

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
  late DateTime _deadline; // elapsed-time based (M1.2): immune to timer drift
  int _remaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(Duration(seconds: widget.durationSeconds));
    _remaining = widget.durationSeconds;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) return;
      final int left =
          _deadline.difference(DateTime.now()).inMilliseconds.clamp(0, 1 << 31);
      final int leftSeconds = (left / 1000).ceil();
      if (left <= 0) {
        timer.cancel();
        Navigator.of(context).pop(true);
      } else if (leftSeconds != _remaining) {
        // Haptic tick each second so the countdown is felt, not just seen.
        HapticFeedback.mediumImpact();
        setState(() => _remaining = leftSeconds);
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
    // M1.2: Android back must NOT bypass the countdown — only the explicit
    // huge CANCEL button aborts the dispatch (PopScope canPop: false).
    return PopScope(
      canPop: false,
      child: AlertDialog(
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
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: _remaining / widget.durationSeconds,
                      strokeWidth: 10,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    ),
                  ),
                  Text(
                    "$_remaining",
                    style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Dispatching SOS alert to responders and contacts in $_remaining seconds...",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              "Tap CANCEL SOS immediately if triggered by accident.",
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
                backgroundColor: Colors.grey.shade900,
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.redAccent, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _cancel,
              icon: const Icon(Icons.close, size: 28),
              label: const Text(
                "CANCEL SOS",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// F5-3: Realistic incoming call overlay for discreet de-escalation in domestic violence or stalker situations.
/// Honest framing: UI-level discretion only. Does not disguise app in system recents or app drawer without native launcher alias.
class FakeCallOverlay extends StatefulWidget {
  const FakeCallOverlay({super.key});

  @override
  State<FakeCallOverlay> createState() => _FakeCallOverlayState();
}

class _FakeCallOverlayState extends State<FakeCallOverlay> {
  bool _isAnswered = false;
  int _seconds = 0;
  Timer? _timer;
  String _callerName = "Mom";
  bool _isMuted = false;
  bool _isSpeaker = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _answer() {
    // Double-tap guard: a second tap must not stack another periodic timer.
    if (_isAnswered) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    setState(() {
      _isAnswered = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  void _decline() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _editCallerName() async {
    final controller = TextEditingController(text: _callerName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Caller Name"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter contact name (e.g. Boss, Mom)"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    });
    if (newName != null && newName.isNotEmpty && mounted) {
      setState(() => _callerName = newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        "${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              // Discreet hidden affordance to exit discreet mode at any time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white30, size: 20),
                    tooltip: "Edit caller name",
                    onPressed: _editCallerName,
                  ),
                  GestureDetector(
                    onTap: _decline,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Exit Call",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Contact Avatar
              const CircleAvatar(
                radius: 46,
                backgroundColor: Colors.white12,
                child: Icon(Icons.person, size: 54, color: Colors.white70),
              ),
              const SizedBox(height: 20),

              // Contact Name
              GestureDetector(
                onTap: _editCallerName,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, size: 16, color: Colors.white38),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Status line
              Text(
                _isAnswered ? timeStr : "Incoming Call • Mobile",
                style: TextStyle(
                  color: _isAnswered ? Colors.tealAccent : Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              if (!_isAnswered) ...[
                // Incoming Call Action Buttons (Decline vs Answer)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'fake_decline',
                          backgroundColor: Colors.redAccent,
                          onPressed: _decline,
                          child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 10),
                        const Text("Decline", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'fake_answer',
                          backgroundColor: Colors.green,
                          onPressed: _answer,
                          child: const Icon(Icons.call, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 10),
                        const Text("Answer", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ] else ...[
                // Answered in-call calm screen
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.notes, color: Colors.tealAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Calm Conversation Script",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        "• 'Yes, I'm heading over right now.'\n• 'Everything is fine, see you in 10 minutes.'\n• 'Don't worry, I have the keys with me.'",
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
                // In-call keypad row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(_isMuted ? Icons.mic_off : Icons.mic,
                          color: _isMuted ? Colors.amber : Colors.white70),
                      onPressed: () => setState(() => _isMuted = !_isMuted),
                    ),
                    IconButton(
                      icon: const Icon(Icons.dialpad, color: Colors.white70),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: Icon(_isSpeaker ? Icons.volume_up : Icons.volume_down,
                          color: _isSpeaker ? Colors.tealAccent : Colors.white70),
                      onPressed: () => setState(() => _isSpeaker = !_isSpeaker),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FloatingActionButton(
                  heroTag: 'fake_end_call',
                  backgroundColor: Colors.redAccent,
                  onPressed: _decline,
                  child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 8),
                const Text("End Call", style: TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
