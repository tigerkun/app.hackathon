# SafeSphere Frontend Architecture

The SafeSphere client tier is architected into two complementary presentations:
1. **Flutter Application** (`lib/`, `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`, `assets/`, `pubspec.yaml`): Native, high-performance cross-platform application featuring GPS tracking, "Watch Live Trip" guardian viewing (`/track`), background telephony integration, offline support, and biometrics.
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
- **Presentation Layer**: Flutter StatefulWidget / StatelessWidget pages with responsive glassmorphic cards and WCAG AA contrast compliance. Features dedicated routes for distress broadcasting (`/emergency`), live trip sharing (`/share`), in-app guardian tracking (`/track`), community alerts (`/alerts`), and offline AI safety guidance (`/ai-assistant`).
- **Service Layer**: Dedicated singleton services (`AuthService`, `SafeSphereMapConfig`).
  - **Hardware-Backed PIN Storage**: `FlutterSecureStorage` (Android KeyStore / iOS Keychain) under key `safesphere_user_pin` with automatic migration from legacy unencrypted file storage (`keyPin`) and graceful fallback to local file storage if platform channels throw (e.g. on desktop, web, or headless test runners).
  - **Offline SOS Queue & Storage Keys**:
    - `safesphere_offline_sos_queue`: JSON list of queued SOS alerts (capped at 20 alerts to prevent memory bloat; replayed on app resume or connectivity restore with mutex `_isProcessingSosQueue`).
    - `safesphere_active_sos_id`: Active SOS alert ID.
    - `safesphere_active_sos_resolve_token`: Plaintext resolve token retained locally for self-resolution.
    - `safesphere_user_pin`: Hardware-backed authentication PIN.
  - **Hyperlocal Community Reports**: Bounded proximity queries via `latitude`, `longitude`, and `radiusKm` (1–50 km, default 10 km). When GPS permission is denied or coordinates are unavailable, sends null parameters to fetch the honest global feed rather than substituting a fabricated location.
- **Data & Model Layer**: Immutable Dart models (`Report`, `SafetyMarker`, `UserModel`, `AuthTokens`).
- **Emergency Hardware & Telephony Layer**: Resilient fallback architecture for native telephony dialer and GPS locks with zero crash risk on permission denials. Unconditionally verified national helplines:
  - `112`: National All-in-One Emergency
  - `181`: Women's Helpline
  - `108`: Disaster & Medical Ambulance
  - `101`: Fire Services
  - `1930`: National Cyber Financial Fraud Helpline

## Production Release Build

To build the production release APK configured with your deployed backend URL:

```bash
flutter build apk --release --dart-define=SAFESPHERE_API_URL=https://<render-app>.onrender.com
```

If `--dart-define=SAFESPHERE_API_URL` is omitted, the mobile app defaults to `http://127.0.0.1:3000` for local development.
