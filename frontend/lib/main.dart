import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'data/auth_state.dart';
import 'routes/route_guard.dart';
import 'routes/app_routes.dart';
import 'pages/home_page.dart';
import 'pages/safety_map_page.dart';
import 'pages/report_page.dart';
import 'pages/ai_assistant_page.dart';
import 'pages/community_alerts_page.dart';
import 'pages/share_location_page.dart';
import 'pages/track_session_page.dart';
import 'pages/emergency_page.dart';
import 'pages/about_page.dart';
import 'pages/onboarding_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve persisted session/PIN state BEFORE first route generation.
  // Otherwise initialRoute '/home' is built while AuthState is still 'loading'
  // and the RouteGuard's pin-lock check can never retroactively redirect it.
  await AuthState().initialize();
  runApp(const MyApp());
}

/// Primary route table definition for static verification & fallback resolution
final Map<String, WidgetBuilder> _appRouteMap = {
  '/': (_) => const HomePage(),
  '/home': (_) => const HomePage(),
  '/map': (_) => const SafetyMapPage(),
  '/safety-map': (_) => const SafetyMapPage(),
  '/report': (_) => const ReportPage(),
  '/alerts': (_) => const CommunityAlertsPage(),
  '/ai-assistant': (_) => const AiAssistantPage(),
  '/share': (_) => const ShareLocationPage(),
  '/track': (_) => const TrackSessionPage(),
  '/emergency': (_) => const EmergencyPage(),
  '/about': (_) => const AboutPage(),
  '/onboarding': (_) => const OnboardingPage(),
  '/community': (_) => const CommunityAlertsPage(),
  '/chat': (_) => const AiAssistantPage(),
};

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool dark = true;
  late final AuthState _authState;

  @override
  void initState() {
    super.initState();
    _authState = AuthState();
    _authState.initialize();
  }

  @override
  void dispose() {
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _authState,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          initialRoute: AppRoutes.home,
          onGenerateRoute: (settings) => RouteGuard.generateRoute(settings, _authState),
          onUnknownRoute: (settings) => MaterialPageRoute(
            builder: (_) => const HomePage(),
          ),
        );
      },
    );
  }
}
