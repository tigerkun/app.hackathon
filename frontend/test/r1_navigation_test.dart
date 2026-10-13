import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';
import '../lib/pages/about_page.dart';
import '../lib/pages/ai_assistant_page.dart';
import '../lib/pages/community_alerts_page.dart';
import '../lib/pages/emergency_page.dart';
import '../lib/pages/home_page.dart';
import '../lib/pages/report_page.dart';
import '../lib/pages/safety_map_page.dart';
import '../lib/pages/share_location_page.dart';
import '../lib/widgets/app_drawer.dart';

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
      await tester.pumpAndSettle();
      expect(find.byType(SafetyMapPage), findsOneWidget);

      // Verify that AppBar leading is an interactive button (IconButton or BackButton), NOT an inert Icon
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);

      final iconButtonFinder = find.descendant(
        of: appBarFinder,
        matching: find.byType(IconButton),
      );
      expect(iconButtonFinder, findsOneWidget,
          reason: 'SafetyMapPage must provide an interactive IconButton in leading rather than a static Icon');

      // Tapping leading button pops back to previous page
      await tester.tap(iconButtonFinder);
      await tester.pumpAndSettle();
      expect(find.byType(SafetyMapPage), findsNothing,
          reason: 'Tapping the leading button must pop back to caller route without trapping the user');
    });

    testWidgets('MyApp defines all primary application routes without exceptions',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
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
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('CommunityAlertsPage drawer items route cleanly without crashing',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));
      navigator.pushNamed('/alerts');
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // Open drawer on CommunityAlertsPage
      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      // Find drawer list tiles
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text("Home"), findsOneWidget);
      expect(find.text("Report Near Me"), findsOneWidget);
      expect(find.text("Community Alerts"), findsOneWidget);
      expect(find.text("Safety Assistant"), findsOneWidget);
      expect(find.text("Emergency Info"), findsOneWidget);

      // Tap Safety Assistant tile
      await tester.tap(find.text("Safety Assistant"));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget,
          reason: 'Tapping Safety Assistant in drawer must navigate to AiAssistantPage without route crash');
    });
  });

  group('R1 - Tier 2: Boundary & Corner Cases (Unknown Routes & Aliases)', () {
    testWidgets('Route aliases /community and /chat resolve without throwing unhandled exceptions',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));

      // Test alias /community
      expect(() => navigator.pushNamed('/community'), returnsNormally,
          reason: 'Route alias /community must be handled in routes or via onUnknownRoute/onGenerateRoute');
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();

      // Test alias /chat
      expect(() => navigator.pushNamed('/chat'), returnsNormally,
          reason: 'Route alias /chat must be handled in routes or via onUnknownRoute/onGenerateRoute');
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
    });

    testWidgets('Unknown route fallback handles unmapped route strings gracefully',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final NavigatorState navigator =
          Navigator.of(tester.element(find.byType(HomePage)));

      // Pushing an arbitrary unmapped route should not crash the app with unhandled FlutterError
      var thrown = false;
      try {
        navigator.pushNamed('/completely-unknown-route-xyz');
        await tester.pumpAndSettle();
      } catch (_) {
        thrown = true;
      }
      expect(thrown, isFalse,
          reason: 'MyApp must define onUnknownRoute or onGenerateRoute fallback to prevent fatal crashes on unknown routes');
    });

    testWidgets('Rapid multiple drawer toggles do not corrupt Navigator history',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      for (int i = 0; i < 3; i++) {
        final ScaffoldState scaffold =
            tester.firstState(find.byType(Scaffold));
        scaffold.openDrawer();
        await tester.pump(const Duration(milliseconds: 50));
        scaffold.closeDrawer();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  group('R1 - Tier 3: Cross-Feature Combinations (Deep Navigation Loop)', () {
    testWidgets('Full circular navigation sequence across all app destinations',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final NavigatorState nav =
          Navigator.of(tester.element(find.byType(HomePage)));

      // 1. Home -> Safety Map
      nav.pushNamed('/safety-map');
      await tester.pumpAndSettle();
      expect(find.byType(SafetyMapPage), findsOneWidget);

      // 2. Safety Map -> pop back to Home
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);

      // 3. Home -> Report
      nav.pushNamed('/report');
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);

      // 4. Report -> pop back to Home
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);

      // 5. Home -> Alerts
      nav.pushNamed('/alerts');
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // 6. Alerts -> Assistant
      nav.pushNamed('/ai-assistant');
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);

      // 7. Assistant -> Emergency
      nav.pushNamed('/emergency');
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyPage), findsOneWidget);

      // 8. Emergency -> About
      nav.pushNamed('/about');
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);

      // Pop all back to Home
      nav.pop();
      nav.pop();
      nav.pop();
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  group('R1 - Tier 4: Real-World Scenarios (User Incident Traversal)', () {
    testWidgets('User incident investigation workflow from drawer to map and back',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Open drawer on HomePage
      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      // Tap Community Alerts in AppDrawer
      expect(find.text("Community Alerts"), findsOneWidget);
      await tester.tap(find.text("Community Alerts"));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // Open drawer on CommunityAlertsPage, tap Report Near Me
      final ScaffoldState alertsScaffold =
          tester.firstState(find.byType(Scaffold));
      alertsScaffold.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text("Report Near Me"));
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);

      // Back button in ReportPage pops back to alerts
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);
    });
  });
}
