# SafeSphere Test Infrastructure & Testing Architecture

## 1. Overview & Testing Philosophy

SafeSphere is an emergency assistance and personal safety application where failure or crashes directly jeopardize user safety. The test infrastructure provides an **opaque-box end-to-end (E2E) and integration test harness** designed according to strict verification standards:

1. **Zero-Codegen Platform Mocking**: High-fidelity, pure Dart platform fakes (`FakeUrlLauncherPlatform`, `FakeGeolocatorPlatform`) extending `Fake` with `MockPlatformInterfaceMixin` and registered via `TestDefaultBinaryMessengerBinding`. No flaky code generators, daemons, or `build_runner` dependencies are required.
2. **Four-Tier Verification Matrix**:
   - **Tier 1: Feature Coverage (Happy Path)** — Primary flows for every screen, intent, route, and data store.
   - **Tier 2: Boundary & Corner Cases** — Extreme dimensions, unmounted state teardown, rapid-message bursts, null/denied permissions, unicode/emoji sanitization.
   - **Tier 3: Cross-Feature Combinations** — Multi-page transitions, state persistence across navigation, sequential emergency actions (dial → location share → report submission).
   - **Tier 4: Real-World Scenarios** — Panicked lone-commuter workflows, rapid emergency alerts, accessibility compliance under low-light conditions.
3. **Progressive Testability & Independence**: Each test file is completely isolated and self-contained, resetting singletons, memory stores (`ReportStore`), and binary messenger handlers in `setUp()` and `tearDown()`.

---

## 2. Directory Layout

```
test/
├── helpers/
│   └── wcag_contrast.dart              # WCAG 2.1 relative luminance and contrast ratio calculator
├── mocks/
│   ├── fake_geolocator.dart             # Pure Dart GeolocatorPlatform fake
│   ├── fake_geolocator_platform.dart    # Export alias for geolocator mock
│   ├── fake_url_launcher.dart          # Pure Dart UrlLauncherPlatform fake
│   └── fake_url_launcher_platform.dart # Export alias for url_launcher mock
├── r1_navigation_test.dart             # R1: Routes, drawer transitions, Map back button, unknown route fallback
├── r2_runtime_stability_test.dart      # R2: Mounted guards, chat race condition, controller disposal, keyboard overflow
├── r3_emergency_actions_test.dart      # R3: 112 dialing, helplines, dynamic GPS retrieval, ReportStore submission
├── r4_architecture_dead_code_test.dart # R4: Dead file pruning, AppTheme deduplication, SafetyMarker model
└── r5_theming_permissions_test.dart    # R5: WCAG AA contrast (AboutPage), app identity, Android/iOS permissions
```

---

## 3. Platform Mocking Layer

### 3.1 `FakeUrlLauncherPlatform` (`test/mocks/fake_url_launcher.dart`)
- **Implements**: `UrlLauncherPlatform` from `url_launcher_platform_interface`.
- **Capabilities**:
  - Intercepts calls to `launchUrl()`, `canLaunch()`, and `launch()`.
  - Records all invoked URLs in `launchedUrls` history for exact assertions.
  - Exposes `canLaunchResult` and `launchResult` boolean triggers for failure testing.
  - Registers binary messenger mock on channel `plugins.flutter.io/url_launcher` as defense-in-depth.
- **Usage**:
  ```dart
  final fakeLauncher = FakeUrlLauncherPlatform();
  setUp(() {
    fakeLauncher.reset();
    fakeLauncher.register();
  });

  testWidgets('Dial 112', (tester) async {
    // ... pump widget and trigger dial ...
    expect(fakeLauncher.launchedUrls.contains('tel:112'), isTrue);
  });
  ```

### 3.2 `FakeGeolocatorPlatform` (`test/mocks/fake_geolocator.dart`)
- **Implements**: `GeolocatorPlatform` from `geolocator_platform_interface`.
- **Capabilities**:
  - Provides mockable device coordinates via `mockPosition` (`Position`).
  - Simulates dynamic location permissions (`LocationPermission.always`, `denied`, `deniedForever`).
  - Simulates hardware service availability via `serviceEnabled` toggle.
  - Supports configurable error injection via `shouldThrowError`.
  - Intercepts binary messenger method channel `flutter.baseflow.com/geolocator`.
- **Usage**:
  ```dart
  final fakeGeolocator = FakeGeolocatorPlatform();
  setUp(() {
    fakeGeolocator.reset();
    fakeGeolocator.register();
  });

  testWidgets('Dynamic GPS', (tester) async {
    fakeGeolocator.mockPosition = Position(latitude: 12.9716, longitude: 77.5946, ...);
    // ... pump widget and trigger location share ...
  });
  ```

### 3.3 `WcagContrast` Helper (`test/helpers/wcag_contrast.dart`)
- **Standard**: WCAG 2.1 Success Criterion 1.4.3 (Contrast Minimum).
- **Algorithm**:
  - Normalizes 8-bit sRGB channels to linear luminance via piecewise IEC 61966-2-1 transfer function:
    $$C_{\text{linear}} = \begin{cases} \frac{C}{12.92} & \text{if } C \le 0.04045 \\ \left(\frac{C + 0.055}{1.055}\right)^{2.4} & \text{if } C > 0.04045 \end{cases}$$
  - Calculates relative luminance: $L = 0.2126 R_{\text{linear}} + 0.7152 G_{\text{linear}} + 0.0722 B_{\text{linear}}$.
  - Alpha-composites translucent foreground colors over background: $C_{\text{comp}} = \alpha \cdot C_{\text{fg}} + (1 - \alpha) \cdot C_{\text{bg}}$.
  - Calculates contrast ratio: $\frac{L_1 + 0.05}{L_2 + 0.05}$.
  - Evaluates normal text ($\ge 4.5:1$) and large text ($\ge 3.0:1$).

---

## 4. Test Suite Inventory & Coverage Mapping

| Test File | Requirement | Tiers Covered | Key Assertions & Targets |
|---|---|---|---|
| `test/r1_navigation_test.dart` | R1 | Tiers 1, 2, 3, 4 | Route strings `/community` → `/alerts`, `/chat` → `/ai-assistant`, Map page `IconButton` leading pop, `onUnknownRoute` fallback, full circular navigation loop. |
| `test/r2_runtime_stability_test.dart` | R2 | Tiers 1, 2, 3, 4 | Mounted guards on 600ms alerts timer, 900ms AI reply timer, rapid chat FIFO queue without `removeLast()` message loss, keyboard 300px inset overflow test on `ReportPage`. |
| `test/r3_emergency_actions_test.dart` | R3 | Tiers 1, 2, 3, 4 | Call Emergency (112), helpline cards (181, 108, 101), dynamic GPS coordinates passed to `Share.share`, GPS permission denied fallback, `ReportStore` submission persistence. |
| `test/r4_architecture_dead_code_test.dart` | R4 | Tiers 1, 2, 3, 4 | `SafetyMarker` model instantiation, 0-byte file remediation, `AppTheme` deduplication (no collision in `lib/data/theme_store.dart`), 10 dead file pruning, `ReportStore` status counts. |
| `test/r5_theming_permissions_test.dart` | R5 | Tiers 1, 2, 3, 4 | Programmatic WCAG AA contrast on `AboutPage` over dark theme (`#0B0F1A`), "SafeSphere" identity in `pubspec.yaml`, `AndroidManifest.xml`, `Info.plist`, UI headers; permissions `INTERNET`, `ACCESS_FINE_LOCATION`, `CALL_PHONE`, `tel:` queries. |

---

## 5. How to Run the Test Suites

When Flutter SDK is available on the machine or in CI:

```bash
# Run all test suites
flutter test

# Run individual requirement suites
flutter test test/r1_navigation_test.dart
flutter test test/r2_runtime_stability_test.dart
flutter test test/r3_emergency_actions_test.dart
flutter test test/r4_architecture_dead_code_test.dart
flutter test test/r5_theming_permissions_test.dart

# Run with verbose stack traces
flutter test --reporter expanded
```
