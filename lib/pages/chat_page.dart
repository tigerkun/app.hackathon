import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/assistant_home.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Safety Assistant',
      body: const AssistantHome(),
    );
  }
}
