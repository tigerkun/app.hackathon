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
import 'widgets/safe_route_page.dart';
import 'widgets/assistant_chat.dart';

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
      routes: {
        '/': (_) => const HomePage(),
        '/map': (_) => const SafetyMapPage(),
        '/report': (_) => const ReportPage(),

        '/safety-map': (_) => const SafetyMapPage(),
        '/ai-assistant': (context) => const AiAssistantPage(),
        '/home': (context) => const HomePage(),
        '/alerts': (context) => const CommunityAlertsPage(),
        '/community': (context) => const CommunityAlertsPage(),

        '/share': (context) => const ShareLocationPage(),
        '/emergency': (context) => const EmergencyPage(),
        '/about': (context) => const AboutPage(),
        '/safe-route': (context) => const SafeRoutePage(),
        '/assistant-chat': (context) => const AssistantChatPage(),
        '/chat': (context) => const AssistantChatPage(),
      },
    );
  }
}
