# SafeSphere Frontend Architecture

The SafeSphere client tier is architected into two complementary presentations:
1. **Flutter Application** (`lib/`, `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`, `assets/`, `pubspec.yaml`): Native, high-performance cross-platform application featuring GPS tracking, background telephony integration, offline support, and biometrics.
2. **Interactive Web Client & Preview** (`web_preview/`): Zero-dependency HTML5/JS web application for immediate emergency access, dispatch viewing, community safety maps, and live tracking.

## Directory Structure
```
frontend/
├── lib/                    # Core Dart source code
│   ├── data/               # Persistent reactive data stores
│   ├── models/             # Immutable data models (UserModel, SafetyMarker, Report)
│   ├── pages/              # Application screens & route targets
│   ├── services/           # Platform integrations & auth API clients
│   ├── theme/              # Cyberpunk glassmorphic dark palette & theming
│   ├── widgets/            # Reusable UI widgets & glass containers
│   └── main.dart           # Application entry point & router table
├── assets/                 # Bundled static assets (Lottie animations, icons)
├── test/                   # Flutter widget tests & adversarial test suites
├── web_preview/            # Standalone zero-dependency HTML5 web preview & server
├── android/                # Native Android runner & Gradle build files
├── ios/                    # Native iOS runner & Xcode workspace
├── web/                    # Flutter web runner & manifest
├── windows/                # Windows desktop runner
├── linux/                  # Linux desktop runner
├── macos/                  # macOS desktop runner
├── pubspec.yaml            # Package definitions & dependency tree
├── pubspec.lock            # Resolved Dart dependency lockfile
└── analysis_options.yaml   # Dart static analysis configuration
```

## State & Layering Standards
- **Presentation Layer**: Flutter StatefulWidget / StatelessWidget pages with responsive glassmorphic cards and WCAG AA contrast compliance.
- **Service Layer**: Dedicated singleton services (`AuthService`, `SafeSphereMapConfig`).
- **Data & Model Layer**: Immutable Dart models (`Report`, `SafetyMarker`, `UserModel`).
- **Emergency Hardware Layer**: Resilient fallback architecture for telephony dialer (`112`, `181`, `108`, `101`) and GPS locks with zero crash risk on permission denials.
