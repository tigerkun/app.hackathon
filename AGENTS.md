# AGENTS.md — SafeSphere Monorepo

Guidance for AI agents and humans working in this repository. Keep this file in
sync when you add commands, conventions, or real-world stubs.

## What this system is

SafeSphere is a personal-safety and emergency-response platform:

- **Distress broadcasting** — one-tap SOS with real device GPS, streamed to a
  monitoring channel over WebSocket (`/ws/sos`) and persisted as an alert.
- **Live guardian tracking** — a broadcaster creates a time-bounded tracking
  session and shares a link; guardians subscribe to the session room and receive
  real-time breadcrumbs.
- **Community incident reporting** — crowdsourced hazard reports and verified
  safety markers (police, hospitals, safe zones), served with Haversine
  proximity search.
- **Multi-modal auth** — email/phone + password, 4–6 digit PIN, phone OTP, and
  an unconditional guest/emergency bypass.
- **AI safety assistant** — conversational guidance UI (backend not yet wired).

The product is deliberately *assistive*, not a replacement for emergency
services. The UI must always make the native dialer (`tel:112`, `tel:181`,
`tel:108`, `tel:101`) reachable.

## Repository layout

```
safesphere/
├── backend/            Node.js (CJS) + Express REST API and `ws` WebSocket server, SQLite store (node:sqlite)
│   ├── src/            routes → controllers → services → models → data/store.js
│   └── tests/          node:test suites (helpers/testApp.js boots an ephemeral server)
├── frontend/           Flutter app (Dart) — no React anywhere
│   ├── lib/            pages, widgets, services, models, data, routes, theme
│   ├── test/           Python AST/adversarial harnesses (no Flutter SDK required)
│   └── web_preview/    zero-dependency HTML5 mock of the client (port 8080)
├── scripts/            dev.js (concurrent servers), test.js (unified gate), clean.js
├── docs/               PRD, architecture, API spec
├── shared/             cross-tier contracts/types
├── .agents/skills/     project runbook skill
└── package.json        root orchestrator
```

## Commands

Run everything from the repo root unless noted.

| Command | What it does |
|---|---|
| `npm run dev` | Backend (:3000) + web preview (:8080) concurrently |
| `npm run backend` | Backend API only |
| `npm run frontend:preview` | Web preview only (`http://127.0.0.1:8080`) |
| `npm test` | Unified gate: frontend structure/imports + backend suite + Python challengers |
| `npm run test:backend` | Backend suite only (`cd backend && npm test`) |
| `cd backend && node --test tests/location_tracking.test.js` | Single backend suite |
| `npm run clean` | Remove build caches/artifacts |

There is **no Flutter SDK installed** in the standard dev/CI environment. Verify
Dart changes by inspection and via `npm test` (which audits relative imports and
runs the Python AST challengers). `npm run test:frontend` (`flutter test`) only
works where the SDK exists.

### Production Android Build (Mobile Client)

To build a release APK connected to a deployed backend (e.g. Render):

```bash
flutter build apk --release --dart-define=SAFESPHERE_API_URL=https://<render-app>.onrender.com
```

If `--dart-define=SAFESPHERE_API_URL` is omitted, the mobile app defaults to `http://127.0.0.1:3000` for local development.

## Architecture

### Backend (layered, CJS)
`routes/` → `controllers/` (HTTP envelopes) → `services/` (domain logic) →
`models/` (entity factories/sanitizers) → `data/store.js` (SQLite
repositories via built-in `node:sqlite` with instant `reset()` for tests).

- Responses use the envelope `{ success: boolean, data?, error?: { code, message, details } }`.
- Storage: Persistent SQLite database driven by Node.js built-in `node:sqlite`
  (`DatabaseSync`). Synchronous execution model matches repository API.
  - Location: `backend/data/safesphere.db` by default in development/production,
    `:memory:` under test runner (`NODE_TEST_CONTEXT` or `NODE_ENV=test`).
    Configurable via `DB_PATH` environment variable.
  - Schema: Hand-managed additive schema (`CREATE TABLE IF NOT EXISTS` and
    `CREATE INDEX IF NOT EXISTS`). No external migration runner (additive
    `ALTER TABLE` / DDL matching repository convention).
  - Refresh tokens: Dual-token security storing both `refreshToken` (plaintext)
    and `refreshTokenHash` (sha256). Verification prefers hash, lazy-migrating
    legacy plaintext sessions upon refresh.
- Auth is dual-token JWT: 15-min access (`JWT_SECRET`) + 7-day refresh
  (`JWT_REFRESH_SECRET`), refresh sessions revocable in `db.sessions`.
- `requireAuth` protects authenticated routes; `optionalAuth` allows guests.
- WebSocket lives at `/ws/sos`: SOS broadcast, plus tracking rooms keyed by
  `sessionId` (`SUBSCRIBE_TRACKING`, `LOCATION_STREAM_UPDATE`, `STREAM_TERMINATE`).

### Frontend (Flutter, React-free)
- `data/auth_state.dart` — `ChangeNotifier` singleton holding auth status
  (`authenticated | guest | pinLocked | otpPending | unauthenticated`).
- `services/auth_service.dart` — REST client for auth, SOS, reports, markers;
  exposes `storage` for direct token reads and fails **honestly** when offline.
- `services/storage_service.dart` — `IStorageService` with file-backed
  persistence and an in-memory fallback.
- `routes/route_guard.dart` — single route resolver enforcing the emergency
  invariant and PIN lock.
- `routes/app_routes.dart` & `main.dart` — declares the static `_appRouteMap` table
  consumed by the Python AST challenger, and wires `RouteGuard.generateRoute`.
- `/track` route & `TrackSessionPage` (`frontend/lib/pages/track_session_page.dart`):
  Dedicated guardian viewer for live tracking sessions ("Watch Live Trip").
- **Guardian Tracking Flow**: Broadcaster initiates a live trip in `ShareLocationPage`
  (`POST /api/v1/location/share-session`), generating a `shareUrl` with format
  `https://<api>/?session=<sessionId>&token=<token>`.
  - **Browser Direct Access (W2-1)**: When opened in any standard web browser, the backend
    directly intercepts `GET /?session=...&token=...` (and `/track`) to serve an inline,
    zero-dependency HTML tracker page with mandatory security headers:
    `Cache-Control: no-store` and `X-Content-Type-Options: nosniff` (ensuring live location
    data is never cached by intermediate proxies or MIME-sniffed). Negative paths fail
    gracefully: missing query tokens render an HTML awaiting/error shell without crashing,
    and missing/invalid tokens on `/api/v1/location/track/:sessionId` return 401 without
    stack trace leakage. The page auto-polls telemetry every 10s, displays live coordinates,
    accuracy, breadcrumb counts, an external Google Maps link, and auto-stops when the session
    ends, with zero paste friction and full XSS-safe textContent escaping.
  - **In-App Viewer**: Guardians using the mobile client open `/track` via AppDrawer
    ("Watch Live Trip"), input the session and token, and subscribe to WebSocket
    `/ws/sos` with `{ type: 'SUBSCRIBE_TRACKING', sessionId, token }`. The guardian
    receives live breadcrumbs via `TRACKING_SNAPSHOT` and `LOCATION_STREAM_UPDATE` packets.
    If the WebSocket drops, the client automatically polls `fetchTrackingSession`.
    When active session expires in < 5 minutes, both mobile broadcaster and watcher show an
    amber "Session expires soon" banner (W2-6).
- **Hyperlocal Community Data (W2-2)**: `GET /api/v1/reports` accepts `latitude`, `longitude`,
    and `radiusKm` query parameters (clamped strictly between 1–50 km, default 10 km). When
    GPS permission is denied or coordinates are unavailable, the frontend honestly passes null
    location parameters to retrieve the unfiltered global feed rather than substituting a
    fabricated Delhi default fix. The empty state honestly reflects distance ("No reports within X km").
- **SOS Broadcast Status & History (W2-3)**: After triggering an SOS alert, `EmergencyPage`
    polls `GET /api/v1/sos/:id` or `/api/v1/sos/active` every 10s, displaying a live status
    banner (`BROADCASTING — N monitors connected`). The `POST /api/v1/sos/trigger` endpoint returns
    a one-time plaintext `resolveToken` credential for self-resolution by the victim or anonymous
    caller; the server only stores a SHA-256 hash (`resolveTokenHash`), which is strictly scrubbed
    from all GET responses (`/sos/active`, `/sos/:id`, `/sos/mine`). Citizens inspect past alerts
    via `GET /api/v1/sos/mine` (supporting optional `?status=active|resolved` filtering). SOS trigger
    invokes `HapticFeedback.heavyImpact()` on confirmed trigger.
- **Hardware-Backed Secure PIN Storage (W2-4)**: Authentication PINs are persisted via
    `FlutterSecureStorage` (KeyStore on Android / Keychain on iOS) under key `safesphere_user_pin`
    with automatic migration from legacy unencrypted file storage (`keyPin`) and graceful fallback
    to file storage if platform channels throw (e.g. desktop/web/headless tests), guaranteeing the
    user is never locked out.
- **Offline SOS Queue & Storage Keys (W2-3/W2-4)**:
    - `safesphere_offline_sos_queue`: JSON list of queued SOS alerts (capped at 20 alerts to prevent
      unbounded storage growth; processed on app resume / connectivity restore with mutex protection).
    - `safesphere_active_sos_id`: Active SOS alert ID.
    - `safesphere_active_sos_resolve_token`: Plaintext resolve token retained locally for self-resolution.
    - `safesphere_user_pin`: Stored authentication PIN.
- **Offline AI Safety Guides (W2-5)**: When the intelligence backend is unreachable,
    `AiAssistantPage` displays static actionable safety protocols (Assault/harassment response,
    Road accident, Cyber fraud, Medical emergency) with national helplines (112, 181, 108, 101, 1930).
    Offline cards are clearly labeled as static guidance without pretending to be a real-time AI persona.
- **`fetchTrackingSession` query parameter design**: Located in
  `frontend/lib/services/auth_service.dart:804`, queries
  `GET /api/v1/location/track/$sessionId?token=${Uri.encodeQueryComponent(trackingToken)}`.
  The tracking token is passed explicitly via query parameter `?token=` rather than
  `Authorization: Bearer` so that a guardian user's own account JWT does not shadow
  or conflict with the session's tracking credential.
- **Report ID Monotonic Suffixes**: In `frontend/lib/pages/report_page.dart:18-20, 120`,
  offline fallback incident report IDs format as
  `rep_${DateTime.now().millisecondsSinceEpoch}_${_localReportSeq++}`. The monotonic
  sequence counter guarantees collision-free IDs during rapid sequential submissions
  within the same millisecond.

## Conventions & invariants

1. **Offline-first resilience.** Storage and network failures must degrade
   gracefully. `StorageService` always falls back to memory; the app must stay
   interactive and able to dial emergency numbers with no backend.
2. **Unconditional emergency-route invariant.** Routes `/emergency` and
   `/share` are **never** blocked by auth, PIN lock, or network state. Emergency
   handlers must dial the native dialer or open a share intent — never an inert
   `() {}` callback.
3. **No fake-success paths.** Never fabricate tokens, sessions, users, OTPs, or
   success responses when the backend is unreachable. Return an honest error and
   surface it to the user. (An earlier version shipped phantom-JWT and hardcoded
   `1234`/`123456` fallbacks; these were removed and must not return.)
4. **The tracking token *is* the credential.** Guest/anonymous tracking is by
   design. Every live-tracking REST call must present the session token
   (`Authorization: Bearer <token>`, `?token=`, or `body.token`), and every
   tracking WebSocket frame must include `token` alongside `sessionId`.
   Mismatches are rejected (`MISSING_TRACKING_TOKEN` / `INVALID_TRACKING_TOKEN`,
   HTTP 401 / WS `ERROR`).
5. **Registration/login PINs are bcrypt-hashed** server-side; never store or
   return plaintext PINs. `toSafeUser` must not leak `passwordHash`, `pin`, or
   `pinHash`.
6. **Production secret hygiene.** In `NODE_ENV=production`, `JWT_SECRET` and
   `JWT_REFRESH_SECRET` are mandatory, ≥32 chars, distinct, and not denylisted —
   startup fails otherwise. Demo seeding is gated by `DEMO_MODE`.
7. **Match existing style; minimal diffs.** CommonJS on the backend, layered
   architecture, standard envelopes. No new dependencies unless already resolved
   in `backend/package.json` / `frontend/pubspec.lock`.

## TODO / real-world integration stubs

Search `TODO(REAL_` for the live list. Current stubs:

| Tag | Location | What remains | Status |
|---|---|---|---|
| `TODO(REAL_SMS_GATEWAY)` | `backend/src/services/sosService.js` | Dispatch SMS to emergency contacts via Twilio / AWS SNS | ACTIVE |
| `TODO(REAL_BACKEND)` | `frontend/lib/services/auth_service.dart` (register, login, OTP send, OTP verify, PIN verify) | Endpoints are live on backend and verified by automated tests | DONE |
| `TODO(REAL_BACKEND)` | `frontend/lib/pages/ai_assistant_page.dart` | Wire AI assistant to a real LLM/Gemini safety endpoint | ACTIVE |
| `TODO(REAL_HARDWARE)` | `frontend/lib/services/auth_service.dart` (`verifyBiometrics`) | Real biometric scan via `local_auth` wired with hardware check and fallback | DONE |

## Known limitations

- **No SMS gateway.** OTP delivery and emergency-contact SMS are not
  implemented; OTP endpoints return dev OTPs only when explicitly enabled.
- **`dart:io` breaks Flutter web.** `auth_service.dart`, `storage_service.dart`,
  and `share_location_page.dart` use `dart:io` (`HttpClient`, `File`, `WebSocket`).
  This is fine on mobile/desktop but will not compile for the `web` target; use
  `web_preview/` for browser demos.
- **Stale/missing `pubspec.lock` entries.** The lockfile does not list every
  direct dependency (e.g. `geolocator`, `google_maps_flutter`, `local_auth`, `flutter_secure_storage`). Run
  `flutter pub get` on a Flutter-equipped machine before building; do NOT edit `pubspec.lock` by hand.
- **`map_config.dart` API key is a placeholder** (`YOUR_GOOGLE_MAPS_API_KEY_HERE`);
  `SafeSphereMapConfig.isConfigured` is `false` until a real key is provided.
- **AI assistant is UI-only** and returns a fixed "awaiting backend" reply.
- Duplicate export shims (`lib/pages/login_page.dart`, `signup_page.dart`,
  `auth_pin_page.dart`) re-export the real pages under `lib/pages/auth/` and must
  be kept for compatibility with the structural verifier.

## Testing & verification

```bash
# Full gate (recommended)
npm test

# Backend only — 169 tests across 42 suites
cd backend && npm test

# Individual backend suites
cd backend
node --test tests/location_tracking.test.js   # live tracking + token gating
node --test tests/auth.test.js
node --test tests/security_hardening.test.js
node --test tests/reports_markers.test.js

# Python challengers (frontend structure, routes, AST invariants, permissions)
python frontend/test/adversarial_r1_challenger_test.py
python frontend/test/challenger_m2_empirical_test.py
python frontend/test/test_r5_permissions_contrast.py
```

All of the above must pass before considering a change complete. Commit per logical fix
and push to origin/main as authorized.
