import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/auth_state.dart';
import '../lib/main.dart';
import '../lib/pages/about_page.dart';
import '../lib/pages/ai_assistant_page.dart';
import '../lib/pages/community_alerts_page.dart';
import '../lib/pages/emergency_page.dart';
import '../lib/pages/home_page.dart';
import '../lib/pages/report_page.dart';
import '../lib/pages/safety_map_page.dart';
import '../lib/pages/share_location_page.dart';
import '../lib/services/auth_service.dart';
import '../lib/services/storage_service.dart';
import '../lib/widgets/app_drawer.dart';

class _MemoryStorageService implements IStorageService {
  final Map<String, String> _values = {};

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}

Future<void> _pumpMyApp(WidgetTester tester) async {
  AuthState(authService: AuthService(storage: _MemoryStorageService()));
  await AuthState().completeOnboarding();
  await tester.pumpWidget(const MyApp());
  await _pumpRouteTransition(tester);
}

Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('R1 - Tier 1: Feature Coverage (Drawer Routes & Map Back Button)', () {
    testWidgets('SafetyMapPage AppBar leading widget is an interactive back button, not static Icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SafetyMapPage()),
                ),
                child: const Text('Open Map'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Map'));
      await _pumpRouteTransition(tester);
      expect(find.byType(SafetyMapPage), findsOneWidget);

      // Verify that AppBar leading is an interactive button (IconButton or BackButton), NOT an inert Icon
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);

      final iconButtonFinder = find.descendant(
        of: appBarFinder,
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(iconButtonFinder, findsOneWidget,
          reason: 'SafetyMapPage must provide an interactive IconButton in leading rather than a static Icon');

      // Tapping leading button pops back to previous page
      await tester.tap(iconButtonFinder);
      await _pumpRouteTransition(tester);
      expect(find.byType(SafetyMapPage), findsNothing,
          reason: 'Tapping the leading button must pop back to caller route without trapping the user');
    });

    testWidgets('MyApp defines all primary application routes without exceptions',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);
      expect(find.byType(HomePage), findsOneWidget);

      final BuildContext context = tester.element(find.byType(HomePage));
      final NavigatorState navigator = Navigator.of(context);

      final primaryRoutes = [
        '/',
        '/home',
        '/map',
        '/safety-map',
        '/report',
        '/alerts',
        '/ai-assistant',
        '/share',
        '/emergency',
        '/about',
      ];

      for (final route in primaryRoutes) {
        expect(() => navigator.pushNamed(route), returnsNormally,
            reason: 'Route "$route" must be registered and navigable in main.dart');
        if (route == '/map' || route == '/safety-map') {
          await _pumpRouteTransition(tester);
        } else {
          await _pumpRouteTransition(tester);
        }
        navigator.pop();
        if (route == '/map' || route == '/safety-map') {
          await _pumpRouteTransition(tester);
        } else {
          await _pumpRouteTransition(tester);
        }
      }
    });

    testWidgets('CommunityAlertsPage drawer items route cleanly without crashing',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));
      navigator.pushNamed('/alerts');
      await _pumpRouteTransition(tester);
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // Open drawer on CommunityAlertsPage
      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await _pumpRouteTransition(tester);

      // Find drawer list tiles
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text("Home"), findsOneWidget);
      expect(find.text("Report Near Me"), findsOneWidget);
      final drawer = find.byType(Drawer);
      expect(
        find.descendant(of: drawer, matching: find.text("Community Alerts")),
        findsOneWidget,
      );
      expect(find.text("AI Assistant"), findsOneWidget);
      expect(find.text("Emergency"), findsOneWidget);

      // Tap AI Assistant tile
      await tester.tap(
        find.descendant(of: drawer, matching: find.text("AI Assistant")),
      );
      await _pumpRouteTransition(tester);
      expect(find.byType(AiAssistantPage), findsOneWidget,
          reason: 'Tapping Safety Assistant in drawer must navigate to AiAssistantPage without route crash');
    });
  });

  group('R1 - Tier 2: Boundary & Corner Cases (Unknown Routes & Aliases)', () {
    testWidgets('Route aliases /community and /chat resolve without throwing unhandled exceptions',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));

      // Test alias /community
      expect(() => navigator.pushNamed('/community'), returnsNormally,
          reason: 'Route alias /community must be handled in routes or via onUnknownRoute/onGenerateRoute');
      await _pumpRouteTransition(tester);
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      navigator.pop();
      await _pumpRouteTransition(tester);

      // Test alias /chat
      expect(() => navigator.pushNamed('/chat'), returnsNormally,
          reason: 'Route alias /chat must be handled in routes or via onUnknownRoute/onGenerateRoute');
      await _pumpRouteTransition(tester);
      expect(find.byType(AiAssistantPage), findsOneWidget);
    });

    testWidgets('Unknown route fallback handles unmapped route strings gracefully',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));

      // Pushing an arbitrary unmapped route should not crash the app with unhandled FlutterError
      var thrown = false;
      try {
        navigator.pushNamed('/completely-unknown-route-xyz');
        await _pumpRouteTransition(tester);
      } catch (_) {
        thrown = true;
      }
      expect(thrown, isFalse,
          reason: 'MyApp must define onUnknownRoute or onGenerateRoute fallback to prevent fatal crashes on unknown routes');
    });

    testWidgets('Rapid multiple drawer toggles do not corrupt Navigator history',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      for (int i = 0; i < 3; i++) {
        final ScaffoldState scaffold =
            tester.firstState(find.byType(Scaffold));
        scaffold.openDrawer();
        await tester.pump(const Duration(milliseconds: 50));
        scaffold.closeDrawer();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _pumpRouteTransition(tester);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  group('R1 - Tier 3: Cross-Feature Combinations (Deep Navigation Loop)', () {
    testWidgets('Full circular navigation sequence across all app destinations',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      final NavigatorState nav =
          Navigator.of(tester.element(find.byType(HomePage)));

      // 1. Home -> Safety Map
      nav.pushNamed('/safety-map');
      await _pumpRouteTransition(tester);
      expect(find.byType(SafetyMapPage), findsOneWidget);

      // 2. Safety Map -> pop back to Home
      nav.pop();
      await _pumpRouteTransition(tester);
      expect(find.byType(HomePage), findsOneWidget);

      // 3. Home -> Report
      nav.pushNamed('/report');
      await _pumpRouteTransition(tester);
      expect(find.byType(ReportPage), findsOneWidget);

      // 4. Report -> pop back to Home
      nav.pop();
      await _pumpRouteTransition(tester);
      expect(find.byType(HomePage), findsOneWidget);

      // 5. Home -> Alerts
      nav.pushNamed('/alerts');
      await _pumpRouteTransition(tester);
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // 6. Alerts -> Assistant
      nav.pushNamed('/ai-assistant');
      await _pumpRouteTransition(tester);
      expect(find.byType(AiAssistantPage), findsOneWidget);

      // 7. Assistant -> Emergency
      nav.pushNamed('/emergency');
      await _pumpRouteTransition(tester);
      expect(find.byType(EmergencyPage), findsOneWidget);

      // 8. Emergency -> About
      nav.pushNamed('/about');
      await _pumpRouteTransition(tester);
      expect(find.byType(AboutPage), findsOneWidget);

      // Pop all back to Home
      nav.pop();
      nav.pop();
      nav.pop();
      nav.pop();
      await _pumpRouteTransition(tester);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  group('R1 - Tier 4: Real-World Scenarios (User Incident Traversal)', () {
    testWidgets('User incident investigation workflow from drawer to map and back',
        (WidgetTester tester) async {
      await _pumpMyApp(tester);

      // Open drawer on HomePage
      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await _pumpRouteTransition(tester);

      // Tap Community Alerts in AppDrawer
      final communityAlertsItem = find.descendant(
        of: find.byType(Drawer),
        matching: find.text("Community Alerts"),
      );
      expect(communityAlertsItem, findsOneWidget);
      await tester.tap(communityAlertsItem);
      await _pumpRouteTransition(tester);
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // Open drawer on CommunityAlertsPage, tap Report Near Me
      final ScaffoldState alertsScaffold =
          tester.firstState(find.byType(Scaffold));
      alertsScaffold.openDrawer();
      await _pumpRouteTransition(tester);

      await tester.tap(find.text("Report Near Me"));
      await _pumpRouteTransition(tester);
      expect(find.byType(ReportPage), findsOneWidget);

      // Back button in ReportPage pops back to alerts
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await _pumpRouteTransition(tester);
      expect(find.byType(CommunityAlertsPage), findsOneWidget);
    });
  });
}
