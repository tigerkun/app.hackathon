import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';

/// ------------------------------------------------------------
/// CHAT MESSAGE MODEL
/// ------------------------------------------------------------
class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isTyping;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isTyping = false,
  });
}

/// ------------------------------------------------------------
/// TYPING TEXT ANIMATION
/// ------------------------------------------------------------
class TypingText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const TypingText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText> {
  String _displayed = '';
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_index < widget.text.length) {
        _index++;
        setState(() {
          _displayed = widget.text.substring(0, _index);
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_displayed, style: widget.style);
  }
}

/// ------------------------------------------------------------
/// AI PULSE HEADER
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
        builder: (context, child) {
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

  final List<_ChatMessage> messages = [
    const _ChatMessage(
      text:
          "Hi 👋 I’m your Safety Assistant.\nTell me what’s going on and I’ll guide you calmly.",
      isUser: false,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(_ChatMessage(text: text, isUser: true));
      messages.add(const _ChatMessage(text: '', isUser: false, isTyping: true));
      _controller.clear();
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        if (messages.isNotEmpty && messages.last.isTyping) {
          messages.removeLast();
        }
        messages.add(
          _ChatMessage(
            text: _generateReply(text),
            isUser: false,
          ),
        );
      });
    });
  }

  String _generateReply(String input) {
    final lower = input.toLowerCase();

    if (lower.contains("follow")) {
      return "If you feel followed, move to a crowded or well-lit area and keep your phone accessible.";
    } else if (lower.contains("unsafe") || lower.contains("scared")) {
      return "You’re not alone. Stay calm, trust your instincts, and consider sharing your live location.";
    } else if (lower.contains("accident")) {
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
                return _ChatBubble(
                  key: ValueKey(index),
                  message: messages[index],
                );
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
                        const Icon(Icons.send, color: AppColors.purple),
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

  const _ChatBubble({super.key, required this.message});

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
