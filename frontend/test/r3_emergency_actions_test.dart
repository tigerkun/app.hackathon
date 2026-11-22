import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../lib/data/report_store.dart';
import '../lib/pages/emergency_page.dart';
import '../lib/pages/report_page.dart';
import '../lib/pages/share_location_page.dart';
import 'mocks/fake_geolocator.dart';
import 'mocks/fake_url_launcher.dart';

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

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
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'share' || methodCall.method == 'shareUri') {
          lastSharedText = methodCall.arguments['text'] as String?;
          return 'success';
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
          return 'success';
        }
        return null;
      },
    );

    ReportStore.clear();
  });

  tearDown(() {
    ReportStore.clear();
  });

  group('R3 - Tier 1: Feature Coverage (Emergency Actions & Dynamic GPS)', () {
    testWidgets('Tapping Call Emergency card launches tel:112 via url_launcher',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await _pumpUi(tester);

      // Find and tap the Call Emergency card (title: "Call Emergency", subtitle: "Dial 112 for immediate help")
      final emergencyCardFinder = find.text("Call Emergency");
      expect(emergencyCardFinder, findsOneWidget);

      await tester.tap(emergencyCardFinder);
      await _pumpUi(tester);

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
      await _pumpUi(tester);

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
        await _pumpUi(tester);

        expect(fakeLauncher.launchedUrls.contains(expectedTel), isTrue,
            reason: 'Tapping "$title" must launch "$expectedTel" via url_launcher');
      }
    });

    testWidgets('ShareLocationPage shares current GPS coordinates from geolocator mock',
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
      await _pumpUi(tester);

      final shareButton = find.text("Share Current Location (One-shot)");
      expect(shareButton, findsOneWidget);

      await tester.ensureVisible(shareButton);
      await _pumpUi(tester);
      await tester.tap(shareButton);
      await _pumpUi(tester);

      expect(lastSharedText, isNotNull,
          reason: 'Tapping the one-shot location action must invoke platform Share');
      expect(lastSharedText!.contains('12.9716') && lastSharedText!.contains('77.5946'), isTrue,
          reason: 'Shared location must dynamically include device GPS coordinates from geolocator rather than hardcoded 28.6139, 77.2090');
    });

    testWidgets('ReportPage does not cache a guest submission as successful',
        (WidgetTester tester) async {
      expect(ReportStore.total, 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await _pumpUi(tester);

      final descField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == "Describe what happened...",
      );
      expect(descField, findsOneWidget);
      await tester.enterText(descField, "Streetlights broken near terminal");

      // Tap Submit Report button
      final submitButton = find.text("Submit Report");
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await _pumpUi(tester);

      expect(ReportStore.total, 0,
          reason: 'A guest/offline submission must not be represented as successfully sent');
      expect(
        find.textContaining("Sign in with a verified account"),
        findsOneWidget,
      );
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
      await _pumpUi(tester);

      // Tap the one-shot share button; denied GPS must remain safe and honest.
      final shareButton = find.text("Share Current Location (One-shot)");
      await tester.ensureVisible(shareButton);
      await _pumpUi(tester);
      await tester.tap(shareButton);
      await _pumpUi(tester);

      expect(tester.takeException(), isNull,
          reason: 'Denied location permissions must not cause unhandled crashes in ShareLocationPage');
    });

    testWidgets('Guest multiline reports are preserved but never falsely cached',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await _pumpUi(tester);

      const complexInput =
          "Emergency alert! \nSpecial chars: <>&\"'\\/\nUnicode emojis: 🚨⚠️📍\nCoordinates: 28.6139° N, 77.2090° E";

      final descField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == "Describe what happened...",
      );
      await tester.enterText(descField, complexInput);
      expect(tester.widget<TextField>(descField).controller!.text, complexInput);

      await tester.tap(find.text("Submit Report"));
      await _pumpUi(tester);

      expect(ReportStore.total, 0,
          reason: 'Unconfirmed reports must not be cached as submitted');
    });

    testWidgets('Consecutive rapid dials are recorded cleanly in url_launcher history',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmergencyPage(),
        ),
      );
      await _pumpUi(tester);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text("Call Emergency"));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _pumpUi(tester);

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
      await _pumpUi(tester);

      // Step 1: Emergency Dial
      await tester.tap(find.text("Call Emergency"));
      await _pumpUi(tester);
      expect(fakeLauncher.launchedUrls.contains('tel:112'), isTrue);

      // Step 2: Share location
      final NavigatorState nav =
          Navigator.of(tester.element(find.byType(EmergencyPage)));
      nav.pushNamed('/share');
      await _pumpUi(tester);
      expect(find.byType(ShareLocationPage), findsOneWidget);

      final shareButton = find.text("Share Current Location (One-shot)");
      await tester.ensureVisible(shareButton);
      await _pumpUi(tester);
      await tester.tap(shareButton);
      await _pumpUi(tester);
      expect(lastSharedText?.contains('19.076'), isTrue);

      // Step 3: File incident report
      nav.pushNamed('/report');
      await _pumpUi(tester);
      expect(find.byType(ReportPage), findsOneWidget);

      final descField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == "Describe what happened...",
      );
      await tester.enterText(descField, "Crisis reported and authority dialed");
      await tester.tap(find.text("Submit Report"));
      await _pumpUi(tester);

      expect(ReportStore.total, 0,
          reason: 'A guest report attempt must not appear as a successful submission');
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
      await _pumpUi(tester);

      // 1. Dial Emergency 112
      await tester.tap(find.text("Call Emergency"));
      await _pumpUi(tester);
      expect(fakeLauncher.lastLaunchedUrl, 'tel:112');

      // 2. Dial Women Helpline 181
      await tester.tap(find.text("Women Helpline"));
      await _pumpUi(tester);
      expect(fakeLauncher.lastLaunchedUrl, 'tel:181');

      // 3. Dial Ambulance 108
      await tester.tap(find.text("Ambulance"));
      await _pumpUi(tester);
      expect(fakeLauncher.lastLaunchedUrl, 'tel:108');
    });
  });
}
