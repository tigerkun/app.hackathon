# SafeSphere Frontend Architecture

The SafeSphere client tier is architected into two complementary presentations:
1. **Flutter Mobile Application** (`lib/`, `android/`, `ios/`, `pubspec.yaml`): Native, high-performance cross-platform application for iOS & Android featuring GPS tracking, background hardware integration, offline support, and biometrics.
2. **Interactive Web Client & Preview** (`web_preview/` / `frontend/web_preview/`): Zero-install web application for immediate emergency access, dispatch viewing, community safety maps, and live tracking URLs.

## Directory Structure
```
frontend/
├── mobile/                 # Architecture guides, API clients, platform bindings
├── web_preview/            # Interactive HTML5/JS web dashboard & preview server
└── README.md               # Frontend integration documentation
```

## State & Layering Standards
- **Presentation Layer**: Flutter StatefulWidget / StatelessWidget pages with responsive glassmorphic cards and WCAG AA contrast compliance.
- **Service Layer**: Dedicated singleton services (`AuthService`, `SafeSphereMapConfig`, `GeolocatorPlatform`).
- **Data & Model Layer**: Immutable Dart models (`Report`, `SafetyMarker`, `UserModel`).
- **Emergency Hardware Layer**: Resilient fallback architecture for telephony dialer (`112`, `181`, `108`, `101`) and GPS locks with zero crash risk on permission denials.
