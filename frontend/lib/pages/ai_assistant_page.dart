import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/typing_text.dart';

/// ------------------------------------------------------------
/// CHAT MESSAGE MODEL (FIXED: was missing)
/// ------------------------------------------------------------
class _ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final bool isTyping;

  _ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.isTyping = false,
  });
}

/// ------------------------------------------------------------
/// AI PULSE HEADER (UNCHANGED)
/// ------------------------------------------------------------
class AiPulseHeader extends StatefulWidget {
  const AiPulseHeader({super.key});

  @override
  State<AiPulseHeader> createState() => _AiPulseHeaderState();
}

class _AiPulseHeaderState extends State<AiPulseHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final shift = (_controller.value + i * 0.3) % 1;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 12 + shift * 6,
                height: 12 + shift * 6,
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// ------------------------------------------------------------
/// AI ASSISTANT PAGE
/// ------------------------------------------------------------
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Timer> _pendingTimers = [];
  int _messageSeq = 0;
  bool _showOfflineGuides = false;

  final List<_ChatMessage> messages = [
    _ChatMessage(
      id: 'welcome',
      text:
      "Hi 👋 I’m your Safety Assistant.\nTell me what’s going on and I’ll guide you calmly.",
      isUser: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.lastFetchFailed) {
      _showOfflineGuides = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    _pendingTimers.clear();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final int seq = ++_messageSeq;
    final String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final String userMsgId = 'user_${timestamp}_$seq';
    final String typingMsgId = 'typing_${timestamp}_$seq';

    setState(() {
      messages.add(_ChatMessage(id: userMsgId, text: text, isUser: true));
      messages.add(
        _ChatMessage(id: typingMsgId, text: '', isUser: false, isTyping: true),
      );
      _controller.clear();
    });

    _sendPromptToRealAiBackend(text, userMsgId, typingMsgId, timestamp, seq);
  }

  Future<void> _sendPromptToRealAiBackend(
    String prompt,
    String userMsgId,
    String typingMsgId,
    String timestamp,
    int seq,
  ) async {
    // NOTE: Removed hardcoded 4-keyword matcher ("follow", "unsafe", "accident") and fake 900ms timer.
    // TODO(REAL_BACKEND): Wire to real Gemini / LLM safety agent endpoint with location context & emergency escalation.
    try {
      // Placeholder response indicating real backend integration requirement:
      if (!mounted) return;
      setState(() {
        _showOfflineGuides = true;
        final typingIndex = messages.indexWhere((m) => m.id == typingMsgId);
        final replyMsg = _ChatMessage(
          id: 'ai_${timestamp}_$seq',
          text: "AI Safety Assistant is awaiting live intelligence backend. In the meantime, actionable protocols and verified helplines are available in the offline guide below. For immediate danger, dial 112.",
          isUser: false,
        );
        if (typingIndex != -1) {
          messages[typingIndex] = replyMsg;
        } else {
          messages.add(replyMsg);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showOfflineGuides = true;
        final typingIndex = messages.indexWhere((m) => m.id == typingMsgId);
        if (typingIndex != -1) {
          messages[typingIndex] = _ChatMessage(
            id: 'err_${timestamp}_$seq',
            text: "Connection error contacting AI safety service. Offline guide cards displayed below.",
            isUser: false,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("AI Safety Assistant"),
      ),
      body: Column(
        children: [
          const AiPulseHeader(),

          /// CHAT AREA
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _ChatBubble(message: messages[index]);
              },
            ),
          ),

          /// OFFLINE SAFETY GUIDES (W2-5)
          if (_showOfflineGuides || AuthService.instance.lastFetchFailed)
            _buildOfflineSafetyGuides(),

          /// INPUT BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: GlassContainer(
              borderColor: AppColors.purple,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Describe what’s happening...",
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon:
                    const Icon(Icons.arrow_upward, color: AppColors.purple),
                    onPressed: _sendMessage,
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineSafetyGuides() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              Icon(Icons.offline_bolt, color: AppColors.teal, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Offline guide — not a substitute for professional help",
                  style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _offlineSafetyCard(
                  title: "Assault/harassment response",
                  steps: const [
                    "Move immediately to a crowded, well-lit store or public area.",
                    "Shout and attract bystander attention to deter perpetrator.",
                    "Call Women Helpline (181) or Police Emergency (112).",
                    "Share live location link or trigger SafeSphere SOS.",
                  ],
                  helpline: "Helpline: 181 / 112",
                  cardColor: AppColors.red,
                ),
                _offlineSafetyCard(
                  title: "Road accident",
                  steps: const [
                    "Check for injuries and move to safe roadside away from traffic.",
                    "Dial Ambulance (108) and Police Emergency (112) immediately.",
                    "Do not move unconscious victims unless imminent fire or hazard.",
                    "Record vehicle registration numbers and photograph scene.",
                  ],
                  helpline: "Helpline: 108 / 112",
                  cardColor: AppColors.amber,
                ),
                _offlineSafetyCard(
                  title: "Cyber fraud",
                  steps: const [
                    "Freeze compromised debit/credit cards & netbanking via bank app.",
                    "Dial National Cyber Crime Helpline (1930) within golden hour.",
                    "File formal complaint at cybercrime.gov.in with transaction IDs.",
                    "Never share OTPs, PINs, or install remote access software.",
                  ],
                  helpline: "Helpline: 1930 (Cyber)",
                  cardColor: AppColors.purple,
                ),
                _offlineSafetyCard(
                  title: "Medical emergency",
                  steps: const [
                    "Call Ambulance (108) or National Emergency (112) without delay.",
                    "Check responsiveness & breathing; start chest compressions (CPR).",
                    "Apply firm direct pressure with clean cloth to bleeding wounds.",
                    "Keep patient calm, warm, and airway open until medics arrive.",
                  ],
                  helpline: "Helpline: 108 / 112",
                  cardColor: AppColors.teal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineSafetyCard({
    required String title,
    required List<String> steps,
    required String helpline,
    required Color cardColor,
  }) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: cardColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cardColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(color: Colors.white70, fontSize: 11)),
                        Expanded(
                          child: Text(
                            step,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              helpline,
              style: TextStyle(
                color: cardColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// CHAT BUBBLE (WITH LOTTIE TYPING)
/// ------------------------------------------------------------
class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final align =
    message.isUser ? Alignment.centerRight : Alignment.centerLeft;

    final color = message.isUser
        ? AppColors.purple.withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.12);

    return Align(
      alignment: align,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: message.isTyping
            ? SizedBox(
          height: 36,
          width: 60,
          child: Lottie.asset(
            'assets/lottie/ai_typing.json',
            repeat: true,
          ),
        )
            : message.isUser
            ? Text(
          message.text,
          style: const TextStyle(
              color: Colors.white, fontSize: 14),
        )
            : TypingText(
          text: message.text,
          style: const TextStyle(
              color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}
