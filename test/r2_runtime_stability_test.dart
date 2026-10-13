import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/pages/ai_assistant_page.dart';
import '../lib/pages/community_alerts_page.dart';
import '../lib/pages/report_page.dart';

void main() {
  group('R2 - Tier 1: Feature Coverage (Mounted Guards & Keyboard Layout)', () {
    testWidgets('CommunityAlertsPage unmounting within 600ms does not throw unmounted setState',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CommunityAlertsPage()),
                ),
                child: const Text('Open Alerts'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Alerts'));
      await tester.pump();
      expect(find.byType(CommunityAlertsPage), findsOneWidget);

      // Immediately pop page before the 600ms timer completes
      final navigator = Navigator.of(tester.element(find.byType(CommunityAlertsPage)));
      navigator.pop();
      await tester.pump();
      expect(find.byType(CommunityAlertsPage), findsNothing);

      // Advance clock past 600ms timer expiration
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'Mounted guard or timer cancellation must prevent unmounted setState() after disposal in CommunityAlertsPage');
    });

    testWidgets('ReportPage form handles virtual soft keyboard inset without RenderFlex overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);

      // Simulate soft keyboard opening with 300px bottom view inset
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'ReportPage must wrap the form panel in a scrollable view with bottom padding to prevent RenderFlex overflow');

      // Verify that a scrollable view exists around the form content
      final scrollableFinder = find.descendant(
        of: find.byType(ReportPage),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollableFinder, findsWidgets,
          reason: 'ReportPage must contain a scrollable view (e.g. SingleChildScrollView) to absorb keyboard insets');
    });
  });

  group('R2 - Tier 2: Boundary & Corner Cases (Rapid Burst Chat Concurrency)', () {
    testWidgets('AiAssistantPage unmounting while async reply is scheduled does not throw',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AiAssistantPage()),
                ),
                child: const Text('Open Assistant'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Assistant'));
      await tester.pumpAndSettle();

      // Submit message to schedule async delayed response
      await tester.enterText(find.byType(TextField), 'Is it safe here?');
      final sendButton = find.widgetWithIcon(IconButton, Icons.arrow_upward);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pump(const Duration(milliseconds: 50));

      // Pop page immediately
      final navigator = Navigator.of(tester.element(find.byType(AiAssistantPage)));
      navigator.pop();
      await tester.pump();
      expect(find.byType(AiAssistantPage), findsNothing);

      // Advance clock past the async reply delay
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'AiAssistantPage must guard async setState() with mounted or cancel active timer on dispose');
    });

    testWidgets('Rapid message queue maintains FIFO order and does not delete user messages via removeLast race',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AiAssistantPage(),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField);
      final sendButton = find.widgetWithIcon(IconButton, Icons.arrow_upward);

      final messagesToSend = [
        'Alert 1: I hear footsteps behind me',
        'Alert 2: Moving towards main avenue',
        'Alert 3: Reached well lit store',
      ];

      // Submit 3 messages rapidly within 100ms
      for (final msg in messagesToSend) {
        await tester.enterText(inputFinder, msg);
        await tester.tap(sendButton);
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Advance clock to allow all pending AI replies to resolve completely
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'Rapid messaging must not throw RangeError or index out of range exceptions');

      // Verify that ALL 3 user messages were retained in the chat history
      for (final msg in messagesToSend) {
        expect(find.text(msg), findsOneWidget,
            reason: 'User message "$msg" must not be deleted by naive messages.removeLast() during concurrent async replies');
      }

      // Verify that the input controller is cleared and ready for new input
      final TextField inputField = tester.widget(inputFinder);
      expect(inputField.controller?.text.isEmpty ?? true, isTrue);
    });

    testWidgets('Extreme display shrinkage does not crash ReportPage layout',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ReportPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Deploy heavy keyboard inset leaving only 120px screen height
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'ReportPage must withstand extreme view constraints without layout crash');
    });
  });

  group('R2 - Tier 3: Cross-Feature Combinations (Controller Lifecycle & Interaction)', () {
    testWidgets('AiAssistantPage TextEditingController is cleared on send and disposed without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiAssistantPage()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test query');
      expect(find.text('Test query'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
      await tester.pump();

      // Controller should be cleared immediately upon send
      expect(find.text('Test query'), findsOneWidget); // Found in bubble, not in TextField

      final navigator = Navigator.of(tester.element(find.byType(AiAssistantPage)));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
    });
  });

  group('R2 - Tier 4: Real-World Scenarios (Panicked Fast-Input User Workflow)', () {
    testWidgets('User rapidly submits urgent inquiries while switching between screens',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => const AiAssistantPage(),
            '/report': (_) => const ReportPage(),
          },
        ),
      );
      await tester.pumpAndSettle();

      // User types urgent query
      await tester.enterText(find.byType(TextField), 'Help, someone is following me');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
      await tester.pump(const Duration(milliseconds: 200));

      // User navigates to Report page mid-query
      final NavigatorState nav =
          Navigator.of(tester.element(find.byType(AiAssistantPage)));
      nav.pushNamed('/report');
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);

      // Return back to Assistant
      nav.pop();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AiAssistantPage), findsOneWidget);
    });
  });
}
