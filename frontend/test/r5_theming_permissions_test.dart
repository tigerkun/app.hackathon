import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/pages/about_page.dart';
import '../lib/theme/app_colors.dart';
import '../lib/theme/app_theme.dart';
import '../lib/widgets/app_drawer.dart';
import 'helpers/wcag_contrast.dart';

void main() {
  group('R5 - Tier 1: Feature Coverage (WCAG AA Contrast & Permissions)', () {
    testWidgets('AboutPage body text on dark theme achieves WCAG AA contrast >= 4.5:1',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AboutPage(),
        ),
      );
      await tester.pumpAndSettle();

      final bgDark = AppColors.bgDark; // Color(0xFF0B0F1A)

      // Find all Text widgets in AboutPage
      final textWidgets = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(textWidgets, isNotEmpty);

      for (final textWidget in textWidgets) {
        final textData = textWidget.data ?? '';
        final style = textWidget.style;
        final color = style?.color ?? Colors.white;
        final fontSize = style?.fontSize ?? 14.0;
        final isBold = style?.fontWeight == FontWeight.bold ||
            (style?.fontWeight?.index ?? 0) >= FontWeight.w700.index;

        final isLargeText = fontSize >= 18.0 || (fontSize >= 14.0 && isBold);
        final ratio = WcagContrast.contrastRatio(color, bgDark);

        if (isLargeText) {
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: 'Large text "$textData" ($fontSize pt) must achieve WCAG AA contrast >= 3.0:1 on dark background. Actual: ${ratio.toStringAsFixed(2)}:1');
        } else {
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'Normal text "$textData" ($fontSize pt) must achieve WCAG AA contrast >= 4.5:1 on dark background. Actual: ${ratio.toStringAsFixed(2)}:1');
        }
      }
    });

    test('AndroidManifest.xml contains INTERNET, ACCESS_FINE_LOCATION, CALL_PHONE, and tel: queries', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();

      expect(content.contains('android.permission.INTERNET'), isTrue,
          reason: 'AndroidManifest.xml must declare INTERNET permission');
      expect(content.contains('android.permission.ACCESS_FINE_LOCATION'), isTrue,
          reason: 'AndroidManifest.xml must declare ACCESS_FINE_LOCATION permission');
      expect(content.contains('android.permission.CALL_PHONE'), isTrue,
          reason: 'AndroidManifest.xml must declare CALL_PHONE permission');
      expect(content.contains('android:scheme="tel"'), isTrue,
          reason: 'AndroidManifest.xml must declare <queries> intent for scheme="tel" to support Android 11+ dialer queries');
    });

    test('Info.plist contains location usage description and tel application query scheme', () {
      final plistFile = File('ios/Runner/Info.plist');
      expect(plistFile.existsSync(), isTrue);

      final content = plistFile.readAsStringSync();

      expect(content.contains('NSLocationWhenInUseUsageDescription'), isTrue,
          reason: 'Info.plist must define NSLocationWhenInUseUsageDescription for GPS emergency sharing');
      expect(content.contains('LSApplicationQueriesSchemes') && content.contains('<string>tel</string>'), isTrue,
          reason: 'Info.plist must declare LSApplicationQueriesSchemes with "tel" for telephony launcher');
    });
  });

  group('R5 - Tier 2: Boundary & Corner Cases (Mathematical Contrast Bounds & Identity)', () {
    test('WCAG mathematical contrast bounds verification on edge cases', () {
      // 1. Pure White vs Pure Black
      final maxContrast = WcagContrast.contrastRatio(Colors.white, Colors.black);
      expect(maxContrast, closeTo(21.0, 0.1));

      // 2. Same Color vs Same Color
      final minContrast = WcagContrast.contrastRatio(Colors.black, Colors.black);
      expect(minContrast, closeTo(1.0, 0.01));

      // 3. Known failure case: Colors.black54 on AppColors.bgDark (produces ~1.07:1)
      final defectiveRatio = WcagContrast.contrastRatio(Colors.black54, AppColors.bgDark);
      expect(defectiveRatio, lessThan(2.0),
          reason: 'Colors.black54 on dark background is confirmed defective (fails WCAG AA 4.5:1)');

      // 4. Known passing case: AppColors.textSecondary / white70 on AppColors.bgDark
      final compliantRatio = WcagContrast.contrastRatio(AppColors.textSecondary, AppColors.bgDark);
      expect(compliantRatio, greaterThanOrEqualTo(4.5),
          reason: 'AppColors.textSecondary on AppColors.bgDark must pass WCAG AA (>= 4.5:1)');
    });

    test('Application identity is unified to SafeSphere across pubspec and platform manifests', () {
      // pubspec.yaml
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('name: safesphere'), isTrue,
          reason: 'pubspec.yaml package name must be "safesphere" rather than legacy placeholder "newhere"');

      // AndroidManifest.xml
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android:label="SafeSphere"'), isTrue,
          reason: 'AndroidManifest.xml android:label must be "SafeSphere"');

      // Info.plist
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist.contains('<string>SafeSphere</string>'), isTrue,
          reason: 'Info.plist CFBundleDisplayName must be "SafeSphere"');
    });
  });

  group('R5 - Tier 3: Cross-Feature Combinations (Theme Switching & UI Branding)', () {
    testWidgets('AboutPage UI header displays SafeSphere branding',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AboutPage(),
        ),
      );
      await tester.pumpAndSettle();

      // UI Title should be SafeSphere, not generic "Safety App"
      expect(find.text("SafeSphere"), findsOneWidget,
          reason: 'AboutPage headline must display "SafeSphere" application identity instead of generic "Safety App"');
      expect(find.text("Safety App"), findsNothing,
          reason: 'Generic placeholder "Safety App" must be eliminated');
    });

    testWidgets('AppDrawer header displays SafeSphere branding',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            drawer: AppDrawer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text("SafeSphere"), findsOneWidget,
          reason: 'AppDrawer header must display "SafeSphere" branding');
    });
  });

  group('R5 - Tier 4: Real-World Scenarios (App Store & Accessibility Compliance)', () {
    test('Light theme background also satisfies WCAG AA contrast standards', () {
      final bgLight = AppColors.bgLight; // Color(0xFFF6F7FB)
      final primaryText = Colors.black87;

      final ratio = WcagContrast.contrastRatio(primaryText, bgLight);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Primary text on light theme background must satisfy WCAG AA (>= 4.5:1)');
    });
  });
}
