import 'package:flutter/material.dart';

class AssistantChatPage extends StatefulWidget {
  const AssistantChatPage({super.key});

  @override
  State<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends State<AssistantChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [
    const {
      'role': 'assistant',
      'text': 'Hi 👋 I’m your Safety Assistant.\nTell me what’s going on — I’m here to help calmly.'
    }
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
      _messages.add({'role': 'user', 'text': text});
      _messages.add({
        'role': 'assistant',
        'text': _mockResponse(text),
      });
    });

    _controller.clear();
  }

  String _mockResponse(String input) {
    final lowerInput = input.toLowerCase();

    if (lowerInput.contains('follow') || lowerInput.contains('unsafe')) {
      return "Thanks for telling me. Try moving to a well-lit, populated area and keep your phone accessible. If you feel threatened, consider calling emergency services.";
    }

    if (lowerInput.contains('night') || lowerInput.contains('dark')) {
      return "Night travel can feel stressful. Stick to familiar routes, share your location with someone you trust, and avoid isolated areas.";
    }

    if (lowerInput.contains('help')) {
      return "You’re not alone. You can inform trusted contacts or use the emergency call option if needed.";
    }

    return "I understand. Stay aware of your surroundings and let me know if you want guidance or quick actions.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        title: const Text('Safety Assistant'),
        backgroundColor: const Color(0xFF0B1220),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';

                return Align(
                  key: ValueKey(i),
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.blueAccent
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      msg['text']!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type your concern...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _sendMessage,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
