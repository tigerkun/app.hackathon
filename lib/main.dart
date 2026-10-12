import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/safety_map_page.dart';
import 'pages/report_page.dart';
import 'pages/ai_assistant_page.dart';
import 'pages/community_alerts_page.dart';
import 'pages/share_location_page.dart';
import 'pages/emergency_page.dart';
import 'pages/about_page.dart';
import 'pages/chat_page.dart';
import 'widgets/assistant_chat.dart';
import 'widgets/safe_route_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool dark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/home': (_) => const HomePage(),
        '/map': (_) => const SafetyMapPage(),
        '/safety-map': (_) => const SafetyMapPage(),
        '/report': (_) => const ReportPage(),
        '/ai-assistant': (_) => const AiAssistantPage(),
        '/assistant-chat': (_) => const AssistantChatPage(),
        '/chat': (_) => const ChatPage(),
        '/alerts': (_) => const CommunityAlertsPage(),
        '/community': (_) => const CommunityAlertsPage(),
        '/share': (_) => const ShareLocationPage(),
        '/emergency': (_) => const EmergencyPage(),
        '/about': (_) => const AboutPage(),
        '/safe-route': (_) => const SafeRoutePage(),
      },
    );
  }
}
