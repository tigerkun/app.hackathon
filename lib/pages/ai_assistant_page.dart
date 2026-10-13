import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
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

  final List<_ChatMessage> messages = [
    _ChatMessage(
      id: 'welcome',
      text:
      "Hi 👋 I’m your Safety Assistant.\nTell me what’s going on and I’ll guide you calmly.",
      isUser: false,
    ),
  ];

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

    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 900), () {
      _pendingTimers.remove(timer);
      if (!mounted) return;

      setState(() {
        final typingIndex = messages.indexWhere((m) => m.id == typingMsgId);
        final replyMsg = _ChatMessage(
          id: 'ai_${timestamp}_$seq',
          text: _generateReply(text),
          isUser: false,
        );
        if (typingIndex != -1) {
          messages[typingIndex] = replyMsg;
        } else {
          messages.add(replyMsg);
        }
      });
    });
    _pendingTimers.add(timer);
  }

  String _generateReply(String input) {
    input = input.toLowerCase();

    if (input.contains("follow")) {
      return "If you feel followed, move to a crowded or well-lit area and keep your phone accessible.";
    } else if (input.contains("unsafe") || input.contains("scared")) {
      return "You’re not alone. Stay calm, trust your instincts, and consider sharing your live location.";
    } else if (input.contains("accident")) {
      return "If there’s an accident, ensure you’re safe first. I can guide you to nearby help.";
    } else {
      return "I’m here with you. Can you tell me where you are or what you’re experiencing?";
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
