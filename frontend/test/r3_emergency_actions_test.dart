import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../lib/data/report_store.dart';
import '../lib/models/report_model.dart';
import '../lib/pages/emergency_page.dart';
import '../lib/pages/report_page.dart';
import '../lib/pages/share_location_page.dart';
import 'mocks/fake_geolocator.dart';
import 'mocks/fake_url_launcher.dart';

void main() {
  final fakeLauncher = FakeUrlLauncherPlatform();
  final fakeGeolocator = FakeGeolocatorPlatform();
  String? lastSharedText;

  setUp(() {
    fakeLauncher.reset();
    fakeLauncher.register();

    fakeGeolocator.reset();
    fakeGeolocator.register();

    lastSharedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share/share'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'share' || methodCall.method == 'shareUri') {
          lastSharedText = methodCall.arguments['text'] as String?;
          return true;
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/share'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'share') {
          lastSharedText = methodCall.arguments['text'] as String?;
          return true;
        }
        return null;
      },
    );

    ReportStore.reports.clear();
  });

  tearDown(() {
    ReportStore.reports.clear();
  });

  group('R3 - Tier 1: Feature Coverage (Emergency Actions & Dynamic GPS)', () {
    testWidgets('Tapping Call Emergency card launches tel:112 via url_launcher',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap the Call Emergency card (title: "Call Emergency", subtitle: "Dial 112 for immediate help")
      final emergencyCardFinder = find.text("Call Emergency");
      expect(emergencyCardFinder, findsOneWidget);

      await tester.tap(emergencyCardFinder);
      await tester.pumpAndSettle();

      expect(fakeLauncher.launchedUrls.contains('tel:112'), isTrue,
          reason: 'Tapping Call Emergency must trigger url_launcher with "tel:112"');
    });

    testWidgets('Tapping helpline cards triggers appropriate emergency phone numbers',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await tester.pumpAndSettle();

      final helplineExpectations = {
        'Women Helpline': 'tel:181',
        'Ambulance': 'tel:108',
        'Fire Services': 'tel:101',
      };

      for (final entry in helplineExpectations.entries) {
        final title = entry.key;
        final expectedTel = entry.value;

        final cardFinder = find.text(title);
        expect(cardFinder, findsOneWidget, reason: 'Helpline card "$title" must exist');

        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        expect(fakeLauncher.launchedUrls.contains(expectedTel), isTrue,
            reason: 'Tapping "$title" must launch "$expectedTel" via url_launcher');
      }
    });

    testWidgets('ShareLocationPage fetches dynamic GPS coordinates from geolocator mock',
        (WidgetTester tester) async {
      // Configure dynamic non-Delhi coordinates (e.g. Bangalore: 12.9716, 77.5946)
      fakeGeolocator.mockPosition = Position(
        latitude: 12.9716,
        longitude: 77.5946,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 920.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ShareLocationPage(),
        ),
      );
      await tester.pumpAndSettle();

      final shareButton = find.text("Share My Live Location");
      expect(shareButton, findsOneWidget);

      await tester.tap(shareButton);
      await tester.pumpAndSettle();

      expect(lastSharedText, isNotNull,
          reason: 'Tapping Share My Live Location must invoke platform Share');
      expect(lastSharedText!.contains('12.9716') && lastSharedText!.contains('77.5946'), isTrue,
          reason: 'Shared location must dynamically include device GPS coordinates from geolocator rather than hardcoded 28.6139, 77.2090');
    });

    testWidgets('ReportPage form input persists to ReportStore on submit button tap',
        (WidgetTester tester) async {
      expect(ReportStore.total, 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Select incident type
      final incidentTypeFinder = find.text("Harassment");
      if (incidentTypeFinder.evaluate().isNotEmpty) {
        await tester.tap(incidentTypeFinder);
        await tester.pumpAndSettle();
      }

      // Enter description text
      final descField = find.byType(TextField);
      expect(descField, findsOneWidget);
      await tester.enterText(descField, "Streetlights broken near terminal");
      await tester.pumpAndSettle();

      // Tap Submit Report button
      final submitButton = find.text("Submit Report");
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Assert persistence into ReportStore
      expect(ReportStore.total, 1,
          reason: 'Submitting ReportPage must add a new Report to ReportStore');
      final report = ReportStore.reports.first;
      expect(report.description, "Streetlights broken near terminal");
      expect(report.status, ReportStatus.pending);
    });
  });

  group('R3 - Tier 2: Boundary & Corner Cases (Fallback Coordinates & Input Stress)', () {
    testWidgets('Location sharing falls back gracefully when GPS permission is denied',
        (WidgetTester tester) async {
      fakeGeolocator.permission = LocationPermission.denied;
      fakeGeolocator.serviceEnabled = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: ShareLocationPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap share button
      await tester.tap(find.text("Share My Live Location"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'Denied location permissions must not cause unhandled crashes in ShareLocationPage');
    });

    testWidgets('ReportStore persists multiline description with special symbols and emojis',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await tester.pumpAndSettle();

      const complexInput =
          "Emergency alert! \nSpecial chars: <>&\"'\\/\nUnicode emojis: 🚨⚠️📍\nCoordinates: 28.6139° N, 77.2090° E";

      await tester.enterText(find.byType(TextField), complexInput);
      await tester.pumpAndSettle();

      await tester.tap(find.text("Submit Report"));
      await tester.pumpAndSettle();

      expect(ReportStore.total, 1);
      expect(ReportStore.reports.first.description, complexInput,
          reason: 'ReportStore must preserve emojis, special characters, and newlines without string corruption');
    });

    testWidgets('Consecutive rapid dials are recorded cleanly in url_launcher history',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text("Call Emergency"));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      final dialed112Count =
          fakeLauncher.launchedUrls.where((u) => u == 'tel:112').length;
      expect(dialed112Count, greaterThanOrEqualTo(1),
          reason: 'Emergency dialing should reliably execute intent triggers');
    });
  });

  group('R3 - Tier 3: Cross-Feature Combinations (Emergency Sequence Chain)', () {
    testWidgets('Sequential crisis response: dial 112, share live GPS, file report',
        (WidgetTester tester) async {
      fakeGeolocator.mockPosition = Position(
        latitude: 19.0760,
        longitude: 72.8777,
        timestamp: DateTime.now(),
        accuracy: 8.0,
        altitude: 14.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/emergency': (_) => const EmergencyPage(),
            '/share': (_) => const ShareLocationPage(),
            '/report': (_) => const ReportPage(),
          },
          initialRoute: '/emergency',
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Emergency Dial
      await tester.tap(find.text("Call Emergency"));
      await tester.pumpAndSettle();
      expect(fakeLauncher.launchedUrls.contains('tel:112'), isTrue);

      // Step 2: Share location
      final NavigatorState nav =
          Navigator.of(tester.element(find.byType(EmergencyPage)));
      nav.pushNamed('/share');
      await tester.pumpAndSettle();
      expect(find.byType(ShareLocationPage), findsOneWidget);

      await tester.tap(find.text("Share My Live Location"));
      await tester.pumpAndSettle();
      expect(lastSharedText?.contains('19.076'), isTrue);

      // Step 3: File incident report
      nav.pushNamed('/report');
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);

      await tester.enterText(find.byType(TextField), "Crisis reported and authority dialed");
      await tester.tap(find.text("Submit Report"));
      await tester.pumpAndSettle();

      expect(ReportStore.total, 1);
      expect(ReportStore.reports.first.description, "Crisis reported and authority dialed");
    });
  });

  group('R3 - Tier 4: Real-World Scenarios (Lone Commuter Night Danger Workflow)', () {
    testWidgets('Full panic button workflow during an active danger scenario',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Dial Emergency 112
      await tester.tap(find.text("Call Emergency"));
      await tester.pumpAndSettle();
      expect(fakeLauncher.lastLaunchedUrl, 'tel:112');

      // 2. Dial Women Helpline 181
      await tester.tap(find.text("Women Helpline"));
      await tester.pumpAndSettle();
      expect(fakeLauncher.lastLaunchedUrl, 'tel:181');

      // 3. Dial Ambulance 108
      await tester.tap(find.text("Ambulance"));
      await tester.pumpAndSettle();
      expect(fakeLauncher.lastLaunchedUrl, 'tel:108');
    });
  });
}
