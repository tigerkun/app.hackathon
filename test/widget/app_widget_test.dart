import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newhere/main.dart';
import 'package:newhere/pages/home_page.dart';
import 'package:newhere/pages/report_page.dart';
import 'package:newhere/pages/community_alerts_page.dart';
import 'package:newhere/pages/emergency_page.dart';
import 'package:newhere/data/report_store.dart';

void main() {
  setUp(() {
    ReportStore.clear();
  });

  testWidgets('App renders HomePage initially', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text("How can we help you stay safe today?"), findsOneWidget);
    expect(find.text("Safety Level: Moderate"), findsOneWidget);
  });

  testWidgets('ReportPage allows selecting incident and submitting report', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReportPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Report Incident"), findsOneWidget);
    expect(find.text("Theft"), findsOneWidget);
    expect(find.text("Harassment"), findsOneWidget);

    // Tap Harassment incident chip
    await tester.tap(find.text("Harassment"));
    await tester.pumpAndSettle();

    // Enter description
    await tester.enterText(find.byType(TextField), "Suspicious vehicle seen");
    await tester.pumpAndSettle();

    // Tap Submit
    await tester.tap(find.text("Submit Report"));
    await tester.pumpAndSettle();

    expect(ReportStore.total, equals(1));
    expect(ReportStore.reports.first.type, equals("Harassment"));
    expect(ReportStore.reports.first.description, equals("Suspicious vehicle seen"));
  });

  testWidgets('CommunityAlertsPage renders alerts and filter chips', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CommunityAlertsPage(),
      ),
    );
    await tester.pump(); // Start delayed timer

    expect(find.text("Community Alerts"), findsOneWidget);
    expect(find.text("All"), findsOneWidget);
    expect(find.text("Safety"), findsOneWidget);
    expect(find.text("Civic"), findsOneWidget);

    // Pump to settle the location dialog timer
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    // Tap OK on location dialog if visible
    final okFinder = find.text("OK");
    if (tester.any(okFinder)) {
      await tester.tap(okFinder);
      await tester.pumpAndSettle();
    }

    // Tap Civic filter chip
    await tester.tap(find.byKey(const ValueKey('chip_Civic')));
    await tester.pumpAndSettle();

    expect(find.text("Civic"), findsAtLeastNWidgets(1));
  });

  testWidgets('EmergencyPage displays helplines and actions', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmergencyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Emergency Info"), findsOneWidget);
    expect(find.text("Call Emergency"), findsOneWidget);
    expect(find.text("National Emergency"), findsOneWidget);
    expect(find.text("112"), findsAtLeastNWidgets(1));
  });
}
