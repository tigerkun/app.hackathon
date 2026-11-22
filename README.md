# SafeSphere Enterprise Monorepo

> **SafeSphere** is a personal-safety prototype for emergency response and community information. It includes GPS-based tracking, a "Watch Live Trip" guardian view (`/track`), native-dialer access to helplines (112, 181, 108, 101, 1930), community reports and markers, offline AI safety guides, secure PIN storage, and multi-modal authentication. It is assistive software, not a replacement for emergency services.

---

## 1. Monorepo Architecture

The repository is partitioned into an enterprise-grade monorepo cleanly isolating the frontend client application, backend API services, documentation, shared contracts, and root automation:

```
safesphere/
├── frontend/                   # Standalone Flutter application & Web Preview
│   ├── lib/                    # Flutter Dart source (pages, widgets, services, models)
│   ├── android/                # Native Android runner & Gradle configurations
│   ├── ios/                    # Native iOS runner & Xcode workspace
│   ├── web/                    # Flutter web runner & HTML template
│   ├── windows/                # Flutter Windows desktop runner
│   ├── linux/                  # Flutter Linux desktop runner
│   ├── macos/                  # Flutter macOS desktop runner
│   ├── assets/                 # Bundled static assets (Lottie animations, icons)
│   ├── test/                   # Flutter test suite & adversarial verification harnesses
│   ├── web_preview/            # Zero-dependency interactive web client & preview server
│   ├── pubspec.yaml            # Flutter package manifest & dependencies
│   ├── pubspec.lock            # Resolved Dart package lockfile
│   └── analysis_options.yaml   # Dart static analyzer & linter configuration
├── backend/                    # Dedicated Node.js/Express REST & WebSocket API service
│   ├── src/                    # Layered API source (controllers, services, routes, models)
│   ├── tests/                  # Backend automated integration & unit tests
│   └── package.json            # Backend dependencies & script definitions
├── docs/                       # Architectural documentation & specifications
│   ├── PRD.md                  # Master Product Requirements Document
│   ├── ARCHITECTURE.md         # System architecture & component blueprints
│   └── API_SPEC.md             # OpenAPI REST & WebSocket protocol specifications
├── shared/                     # Cross-tier contracts & schemas
│   ├── contracts/              # OpenAPI / JSON API contracts
│   └── types/                  # TypeScript interface definitions
├── scripts/                    # Cross-platform zero-dependency monorepo automation
│   ├── dev.js                  # Concurrent runner (spawns backend + frontend preview)
│   ├── test.js                 # Unified monorepo verification harness
│   └── clean.js                # Monorepo artifact, cache, and bytecode cleaner
├── package.json                # Root monorepo orchestrator
└── README.md                   # Repository overview & developer guide
```

---

## 2. Root Monorepo Automation

All primary developer workflows are orchestrated via standard `npm` scripts defined in the root `package.json`:

| Script | Command | Description |
|---|---|---|
| `npm run dev` | `node scripts/dev.js` | Concurrently boots both the backend API (Port 3000) and frontend web preview (Port 8080) with graceful shutdown on `Ctrl+C` |
| `npm run backend` | `npm --prefix backend start` | Starts the backend Node.js API service independently |
| `npm run backend:dev` | `npm --prefix backend run dev` | Starts the backend API in hot-reload development mode |
| `npm run frontend:preview` | `node frontend/web_preview/server.js` | Launches the standalone interactive HTML5 web preview on `http://127.0.0.1:8080` |
| `npm test` | `node scripts/test.js` | Runs comprehensive monorepo verification (frontend structure, backend tests, and adversarial suites) |
| `npm run test:backend` | `npm --prefix backend test` | Executes the backend Node.js test suite |
| `npm run test:frontend` | `cd frontend && flutter test` | Executes the Flutter mobile test suite |
| `npm run clean` | `node scripts/clean.js` | Cross-platform cleanup of Flutter build artifacts, pub caches, coverage reports, and bytecode |

---

## 3. Quick Start

### Prerequisites
- **Node.js**: `v18.0.0` or higher (`v24.x` recommended)
- **npm**: `v9.x` or higher
- **Python**: `3.10+` (for verification test harnesses)
- **Flutter SDK**: `3.50.1` (required for Flutter analysis, tests, and native builds; available at `C:\src\flutter` on the Android build machine)

### Development Setup

1. **Clone and Navigate**:
   ```bash
   cd C:\Users\tejas\projects\safesphere
   ```

2. **Launch Development Environment**:
   ```bash
   npm run dev
   ```
   - Frontend Interactive Preview: `http://127.0.0.1:8080`
   - Backend REST & WebSocket API: `http://127.0.0.1:3000`

3. **Run Automated Test Verification**:
   ```bash
   npm test
   ```

4. **Clean Build Caches**:
   ```bash
   npm run clean
   ```

---

## 4. Production Deployment & Builds

### Backend Render Deployment
SafeSphere's backend is configured for deployment as a Render Web Service with persistent SSD disk storage via `render.yaml`. See `.env.example` for required production environment variables.

### Mobile Production Release Build

Ensure dependencies are resolved before building:
```bash
cd frontend
flutter pub get
flutter build apk --release --dart-define=SAFESPHERE_API_URL=https://<render-app>.onrender.com
```

> **Note:** Run `flutter pub get` on a Flutter-equipped machine to resolve newly declared dependencies (`flutter_secure_storage: ^9.2.2`, `local_auth: ^2.3.0`, `path_provider`, `geolocator`). Do not edit `pubspec.lock` by hand.

The Android wrapper uses Gradle `9.5.0`, Android Gradle Plugin `9.3.1`, and Kotlin Gradle Plugin `2.4.20`. Release builds currently use the debug signing key and are **not Play Store-ready** until a private release keystore is configured.

### Browser Live Guardian Tracking & Security Headers
Tracking sessions generated by SafeSphere produce capability share links formatted as `https://<api>/?session=<id>&token=<token>`. Opening this URL or navigating to `/track` in any modern desktop or mobile browser serves an inline, zero-dependency HTML tracker page polling live telemetry every 10 seconds without requiring app installation or authentication.
- **Mandatory Security Headers**: Both `/track` and `GET /?session=...&token=...` strictly enforce:
  - `Cache-Control: no-store` (ensures live GPS coordinates are never cached by browsers, proxies, or CDNs)
  - `X-Content-Type-Options: nosniff` (prevents MIME-sniffing vulnerabilities)
- **Fail-Closed Negative Paths**: Missing session or token query parameters display an HTML awaiting/error state without crashing or leaking stack traces. Missing or invalid tokens on `/api/v1/location/track/:sessionId` return 401 Unauthorized without stack trace disclosure.
- **Mobile Watcher**: Guardians using the mobile client access the session at `/track` via AppDrawer ("Watch Live Trip") with real-time WebSocket telemetry and expiration banners.

### Emergency SOS Lifecycle, History & Offline Queuing
- **One-Time Resolve Token**: Triggering an emergency SOS (`POST /api/v1/sos/trigger`) returns a one-time plaintext `resolveToken` credential for self-resolution by the victim or anonymous caller. The backend stores only a SHA-256 hash (`resolveTokenHash`), strictly redacted from all public and authenticated GET endpoints (`/sos/active`, `/sos/:id`, `/sos/mine`).
- **SOS History & Monitor Count**: `GET /api/v1/sos/mine` enables citizens to review their own past alerts (supporting `?status=active|resolved`), including a live `monitorsConnected` count indicating connected WebSocket responders.
- **Offline SOS Queue**: When device connectivity is unavailable, alerts are queued locally under `safesphere_offline_sos_queue` (capped at 20 alerts) and automatically replayed with mutex protection upon network restoration or app resume. Active session IDs and tokens are maintained under `safesphere_active_sos_id` and `safesphere_active_sos_resolve_token`.
- **Verified Emergency Helplines**: Unconditional native dialer access for:
  - `112`: National Emergency All-in-One
  - `181`: Women Helpline
  - `108`: Disaster & Medical Ambulance
  - `101`: Fire Response
  - `1930`: Cyber Financial Fraud

### Hyperlocal Community Incident Reporting
- `GET /api/v1/reports` supports proximity query parameters: `latitude`, `longitude`, and `radiusKm` (clamped between 1–50 km, default 10 km).
- When GPS permission is denied or coordinates are unavailable, the frontend honestly sends null location parameters to fetch the global feed rather than substituting a fabricated location.

### Hardware-Backed PIN Storage
- User PINs are encrypted via `FlutterSecureStorage` (Android KeyStore / iOS Keychain) under the key `safesphere_user_pin`.
- Includes automatic migration from legacy unencrypted file storage and graceful fallback to secure local storage if hardware platform channels throw (desktop, web preview, or test environments), ensuring users are never locked out of emergency features.

If `--dart-define=SAFESPHERE_API_URL` is omitted, the mobile app defaults to `http://127.0.0.1:3000` for local development.

### Verification boundaries
- Automated checks: `npm test`; with Flutter installed, also run `cd frontend && flutter analyze lib && flutter test`.
- Physical-device workflows (GPS permissions, background beacons, gestures, dialer/share intents), real SMS delivery, provider credentials, live Render redeploy persistence, and release-key signing require their respective devices/accounts and are not established by repository tests or an APK build.
- In production, set `CORS_ORIGIN` to comma-separated exact browser origins. A production `*` is intentionally ignored; requests without an `Origin` header (including native clients) remain supported.

---

## 5. Documentation Hub

Detailed technical specifications and design documents are located in `docs/`:
- **[Master PRD](docs/PRD.md)**: Product vision, user personas, functional specifications, non-functional security SLAs, and release roadmap.
- **[System Architecture](docs/ARCHITECTURE.md)**: Microservices and mobile architecture, data flow diagrams, and state management.
- **[API Specifications](docs/API_SPEC.md)**: OpenAPI 3.0 REST endpoints, dual-token JWT auth lifecycle, and WebSocket location streaming protocol.

---

## 6. License

Copyright © 2026 SafeSphere Platform Team. Released under the MIT License.
