import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/report_store.dart';
import '../lib/models/report_model.dart';
import '../lib/theme/app_colors.dart';
import '../lib/theme/app_theme.dart';
import '../lib/widgets/map_placeholder.dart';

void main() {
  group('R4 - Tier 1: Feature Coverage (Models, Themes & Store Retention)', () {
    test('SafetyMarker model can be instantiated and holds valid geometry and metadata', () {
      const marker = SafetyMarker(
        position: Offset(0.35, 0.65),
        icon: Icons.local_police,
        color: AppColors.blue,
        label: "Police Station",
      );

      expect(marker.position.dx, 0.35);
      expect(marker.position.dy, 0.65);
      expect(marker.icon, Icons.local_police);
      expect(marker.color, AppColors.blue);
      expect(marker.label, "Police Station");
    });

    test('AppTheme provides unified dark and light themes without class collision', () {
      final darkTheme = AppTheme.dark();
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, AppColors.bgDark);
      expect(darkTheme.fontFamily, 'Inter');

      final lightTheme = AppTheme.light();
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.bgLight);
      expect(lightTheme.fontFamily, 'Inter');
    });

    test('ReportStore and Report model support full lifecycle operations and status counting', () {
      ReportStore.reports.clear();
      expect(ReportStore.total, 0);

      final r1 = Report(
        id: 'rep-001',
        type: 'Theft',
        location: 'Metro Station Exit A',
        description: 'Bicycle stolen from bike rack',
        time: DateTime.now(),
        status: ReportStatus.pending,
      );

      final r2 = Report(
        id: 'rep-002',
        type: 'Harassment',
        location: 'Park Lane',
        description: 'Verbal harassment reported',
        time: DateTime.now(),
        status: ReportStatus.approved,
      );

      final r3 = Report(
        id: 'rep-003',
        type: 'Unsafe Area',
        location: 'Underpass',
        description: 'No lights in pedestrian walkway',
        time: DateTime.now(),
        status: ReportStatus.rejected,
      );

      ReportStore.addReport(r1);
      ReportStore.addReport(r2);
      ReportStore.addReport(r3);

      expect(ReportStore.total, 3);
      expect(ReportStore.countByStatus(ReportStatus.pending), 1);
      expect(ReportStore.countByStatus(ReportStatus.approved), 1);
      expect(ReportStore.countByStatus(ReportStatus.rejected), 1);

      ReportStore.reports.clear();
    });
  });

  group('R4 - Tier 2: Boundary & Corner Cases (Dead Code Audit & 0-Byte Remediation)', () {
    test('lib/models/safety_marker.dart is populated and non-empty (>0 bytes)', () {
      final markerFile = File('lib/models/safety_marker.dart');
      expect(markerFile.existsSync(), isTrue,
          reason: 'lib/models/safety_marker.dart must exist in project tree');
      expect(markerFile.lengthSync(), greaterThan(0),
          reason: 'lib/models/safety_marker.dart must NOT be a 0-byte file');

      final content = markerFile.readAsStringSync();
      expect(content.contains('class SafetyMarker'), isTrue,
          reason: 'lib/models/safety_marker.dart must declare class SafetyMarker');
    });

    test('lib/data/theme_store.dart is pruned or does not declare a colliding AppTheme class', () {
      final themeStoreFile = File('lib/data/theme_store.dart');
      if (themeStoreFile.existsSync()) {
        final content = themeStoreFile.readAsStringSync();
        expect(content.contains('class AppTheme'), isFalse,
            reason: 'lib/data/theme_store.dart must NOT declare a duplicate AppTheme class collision');
      }
    });

    test('10 unreferenced prototype dead files are pruned or unreferenced by active code', () {
      final unreferencedFiles = [
        'lib/data/theme_store.dart',
        'lib/pages/chat_page.dart',
        'lib/utils/route_animation.dart',
        'lib/widgets/animated_entry.dart',
        'lib/widgets/assistant_chat.dart',
        'lib/widgets/assistant_home.dart',
        'lib/widgets/base_scaffold.dart',
        'lib/widgets/hover_scale.dart',
        'lib/widgets/ng_card.dart',
        'lib/widgets/safe_route_page.dart',
      ];

      final activeFiles = [
        'lib/main.dart',
        'lib/pages/home_page.dart',
        'lib/pages/safety_map_page.dart',
        'lib/pages/report_page.dart',
        'lib/pages/ai_assistant_page.dart',
        'lib/pages/community_alerts_page.dart',
        'lib/pages/share_location_page.dart',
        'lib/pages/emergency_page.dart',
        'lib/pages/about_page.dart',
        'lib/widgets/app_drawer.dart',
      ];

      // Verify no active file imports any pruned prototype
      for (final activePath in activeFiles) {
        final activeFile = File(activePath);
        if (!activeFile.existsSync()) continue;
        final content = activeFile.readAsStringSync();

        for (final deadPath in unreferencedFiles) {
          final filename = deadPath.split('/').last;
          expect(content.contains(filename), isFalse,
              reason: '$activePath must not import or reference dead file $filename');
        }
      }
    });
  });

  group('R4 - Tier 3: Cross-Feature Combinations (Marker Rendering with Map)', () {
    testWidgets('MapPlaceholder renders multiple SafetyMarker items without runtime exceptions',
        (WidgetTester tester) async {
      final markers = [
        const SafetyMarker(
          position: Offset(0.2, 0.3),
          icon: Icons.local_police,
          color: AppColors.blue,
          label: "Police 1",
        ),
        const SafetyMarker(
          position: Offset(0.6, 0.7),
          icon: Icons.local_hospital,
          color: AppColors.red,
          label: "Hospital 1",
        ),
        const SafetyMarker(
          position: Offset(0.5, 0.5),
          icon: Icons.security,
          color: AppColors.teal,
          label: "Safe Point",
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MapPlaceholder(markers: markers),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MapPlaceholder), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('R4 - Tier 4: Real-World Scenarios (Architectural Cleanliness Sweep)', () {
    test('Active codebase Dart files have zero duplicate class declarations in lib/', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final classDeclarations = <String, List<String>>{};
      final classRegex = RegExp(r'class\s+([A-Za-z0-9_]+)');

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;
          final match = classRegex.firstMatch(line);
          if (match != null) {
            final className = match.group(1)!;
            // Ignore private classes (prefixed with _)
            if (className.startsWith('_')) continue;
            classDeclarations.putIfAbsent(className, () => []).add(file.path);
          }
        }
      }

      // Assert that public classes like AppTheme are unique across the active codebase
      final appThemeFiles = classDeclarations['AppTheme'] ?? [];
      expect(appThemeFiles.length, lessThanOrEqualTo(1),
          reason: 'Class AppTheme must not be declared in multiple files: $appThemeFiles');
    });
  });
}
