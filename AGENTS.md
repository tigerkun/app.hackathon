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
- **AI safety assistant** — conversational guidance UI wired to a Groq-backed
  `POST /api/v1/ai/chat` route, with honest static-guide fallback when the
  backend is unreachable or unconfigured.

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

The standard dev/CI image may not include Flutter. On the Android build machine,
Flutter 3.50.1 is installed at `C:\src\flutter`; run Dart checks from
`frontend\` with `flutter analyze lib` and `flutter test`. The repository gate
`npm test` remains useful in environments without Flutter because it audits
relative imports and runs the Python AST challengers.

### Production Android Build (Mobile Client)

To build a release APK connected to a deployed backend (e.g. Render):

```bash
flutter build apk --release --dart-define=SAFESPHERE_API_URL=https://<render-app>.onrender.com
```

If `--dart-define=SAFESPHERE_API_URL` is omitted, the mobile app defaults to `http://127.0.0.1:3000` for local development.
The Android wrapper requires Gradle 9.5.0, Android Gradle Plugin 9.3.1, and
Kotlin Gradle Plugin 2.4.20. The current release build still uses the debug
signing key; it is not suitable for Play Store distribution until a private
release keystore is configured.

## Architecture

### Backend (layered, CJS)
`routes/` → `controllers/` (HTTP envelopes) → `services/` (domain logic) →
`models/` (entity factories/sanitizers) → `data/store.js` (SQLite
repositories via built-in `node:sqlite` with instant `reset()` for tests).

- Responses use the envelope `{ success: boolean, data?, error?: { code, message, details } }`.
- Production CORS accepts comma-separated exact origins from `CORS_ORIGIN`; `*` is ignored in production and missing Origin headers remain valid for native clients. Public SOS and location mutations have dedicated per-IP limits in addition to the global limiter.
- Storage: SQLite database driven by Node.js built-in `node:sqlite`
  (`DatabaseSync`). Synchronous execution model matches repository API.
  - Location: `backend/data/safesphere.db` by default in development/production,
    `:memory:` under test runner (`NODE_TEST_CONTEXT` or `NODE_ENV=test`).
    Configurable via `DB_PATH` environment variable.
  - **Snapshot persistence mode (free-tier deploys):** when `SUPABASE_URL` +
    `SUPABASE_SERVICE_ROLE_KEY` are set, the live DB runs **in-memory** and
    durability comes from `backend/src/data/dbSnapshot.js`: hydrate at boot
    (node:sqlite `deserialize()` — atomic, before `server.listen()`), serialize
    + upload to a PRIVATE Supabase Storage bucket every 45s (sha256 dirty
    check), final flush in the SIGTERM shutdown chain before `db.close()`.
    A failed/garbage hydrate DISABLES uploads for that process so a fresh empty
    DB can never overwrite the good remote snapshot. node:sqlite `deserialize()`
    must only target in-memory connections — WAL file connections break after
    deserialize ("unable to open database file"). `deserializeSnapshot()`
    re-runs the additive schema catch-up afterwards so snapshots taken by older
    builds are upgraded in place.
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
- **Live AI Safety Assistant (Groq)**: `POST /api/v1/ai/chat` proxies a sanitized prompt
    (1–1000 chars, ≤12 history turns, strict role allowlist) to Groq's OpenAI-compatible
    completions API. `GROQ_API_KEY` is read from env only and never returned/logged; model
    defaults to `openai/gpt-oss-120b` (`GROQ_MODEL` override) with `max_tokens` capped at 400.
    Guest calls allowed via `optionalAuth`, throttled by a dedicated 10/min `aiLimiter`.
    Failures are honest: `503 AI_NOT_CONFIGURED`, `502 AI_UPSTREAM_ERROR` (key never leaked),
    `429 AI_RATE_LIMITED`. On failure the frontend keeps the offline W2-5 guides visible and
    still shows the dial-112 copy.
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
- **SOS Auto-Escalation & Active Watchdog (F3-1)**:
  - 60s periodic escalation tick in `backend/src/services/sosService.js` (unref'd timer, cleared on resolve). For each active alert older than `ESCALATE_AFTER_MS` (default 10min), increments `escalationLevel` (capped at 3) and broadcasts `SOS_ESCALATED` `{ alertId, level, elapsedMin, timestamp }` over WebSocket and re-broadcasts `SOS_ALERT_BROADCAST` to late-joining monitors.
  - SQLite `alerts` schema includes `escalationLevel INTEGER NOT NULL DEFAULT 0`.
  - `GET /api/v1/sos/active` and `GET /api/v1/sos/:id` expose `escalationLevel` and `ageSeconds`.
  - Frontend `EmergencyPage` displays `"ACTIVE — broadcasting Xm"` and an `"ESCALATED ×N"` badge when `escalationLevel > 0`, with honest monitor client copy.
- **Breadcrumb-Stall Guardian Alert (F3-2)**:
  - SQLite `tracking_sessions` tracks `lastActivityAt TEXT` and `lastPingAt TEXT`.
  - `locationController.getTrack` calculates `stallDetected = status === 'active' && (now - lastActivityAt > 120s)` and `stalledDurationSeconds`.
  - Frontend `TrackSessionPage` polls every 4s and displays an amber `"SIGNAL LOST — no update for Xm"` banner when stalled, and a transient `"Signal restored"` banner for one polling cycle upon telemetry resumption.
- **Check-in Timer / Dead-Man Switch (F3-3)**:
  - SQLite `tracking_sessions` tracks `checkInIntervalMin INTEGER`, `checkInDeadline TEXT`, and `missedCheckIns INTEGER DEFAULT 0`.
  - `POST /api/v1/location/share-session` accepts optional `checkInIntervalMin` (1–1440 min) and validates bounds.
  - Background 60s tick checks active sessions where `now > checkInDeadline`, broadcasts `CHECKIN_MISSED` to tracking WebSocket room, and increments `missedCheckIns`. Broadcaster pings reset deadline = `now + interval` and clear missed check-ins.
  - Frontend `ShareLocationPage` provides a check-in interval selector (Off, 15, 30, 60 min) with honest labeling ("alerts monitoring clients & session watchers" — strictly avoiding fake SMS claims), and `TrackSessionPage` shows "Next check-in due HH:MM" and red missed check-in banner.
- **Two-Way SOS Responder Chat (F4-1)**:
  - WebSocket `/ws/sos`: frame `CHAT_MESSAGE` `{ alertId, token | sessionId?, text }`. Auth verifies alert ownership, privileged responder/admin role, or valid `resolveToken`. Broadcasts to alert room.
  - SQLite `sos_messages`: additive table storing `id`, `alertId`, `senderRole`, `senderId`, `text`, `createdAt` with 50-message FIFO cap per alert.
  - Rate limiting: enforced at 1 msg/2s per sender. Max 500 characters.
  - REST fallback: `POST /api/v1/sos/:id/messages` and `GET /api/v1/sos/:id/messages` for environments where WS is dropped or blocked.
  - Frontend `EmergencyPage` renders interactive live chat panel with victim vs responder message distinction, WS streaming, and 5s polling fallback.
- **Panic Gesture & 1-Tap SOS (F4-2 / F4-2-alt)**:
  - Hardware button intercept deferred under `TODO(REAL_HARDWARE)` due to absence of hardware intercept plugin in `pubspec.yaml`.
  - Shipped `F4-2-alt`: persistent 1-tap floating SOS action on `HomePage`, single-gate countdown dialog (`SosCountdownDialog`) without superfluous confirmation dialogs, and lock-screen widget recommendation in `AboutPage`.
- **Onboarding & India DPDP Act Privacy Consent (F4-3)**:
  - 3-screen `OnboardingPage`: (1) assistive scope & 112 priority, (2) permissions rationale, (3) DPDP consent checkbox required before "Get Started".
  - Storage flags: `safesphere_onboarded` ('true'/'false') and `safesphere_privacy_consent` (ISO timestamp + policy version).
  - Invariant #2: `/emergency` and `/share` routes bypass onboarding entirely.
  - `DELETE /api/v1/auth/me`: requires authentication and PIN re-auth, cascadingly deleting user, sessions, alerts, and tracking sessions.
  - Drawer exposes "Privacy & Consent (DPDP)" dialog with consent metadata and account erasure.
- **Marker Verification Admin Queue (F4-4)**:
  - SQLite `markers`: schema includes `status TEXT DEFAULT 'verified'`, `verifiedBy TEXT`, and `verifiedAt TEXT`.
  - `GET /api/v1/markers/pending`: privileged admin/responder only, returns pending marker queue.
  - `POST /api/v1/markers/:id/verify`: `{ approve: boolean }` with privileged role requirement and audit logging.
  - Frontend `/review-markers` (`ReviewMarkersPage`): admin/responder queue with approve/reject workflow.
- **Report Status Lifecycle Visibility (F4-5)**:
  - Valid report statuses: `['pending', 'under_investigation', 'verified', 'resolved', 'rejected']`.
  - `POST /api/v1/reports/:id/status`: privileged status transition endpoint.
  - Frontend `CommunityAlertsPage`: added "Verified only" FilterChip toggle, status badges (`Pending`, `Investigating`, `Verified`, `Resolved`, `Rejected`), and detailed modal report inspection.
- **Trusted Circle Connections & SafeSphere IDs (M3)**:
  - Every user gets a public **Safe ID** (`SF-XXXX-XX`, unambiguous alphabet — no `O/0/I/1`) generated at registration (`users.safeId`, unique index). It is the ONLY address other users need — never an email or phone.
  - `POST /api/v1/connections`: grantee requests by `ownerSafeId` with scopes ⊆ `['location','nearby_alerts','sos_status']` and mode `always | sos_only`. Self-connection 400, unknown Safe ID 404, invalid scope/mode 400, duplicate live pair 409 (`CONNECTION_EXISTS` — one live connection per pair; revoked pairs may re-request), pending cap 20/owner, 25 live connections/grantee.
  - Pending requests expire after 30 days; expiration is applied on reads and expired requests grant no access. Accepted connections do not expire automatically.
  - Respond/revoke: `POST /:id/respond` (owner-only accept; grantee may withdraw own pending), `POST /:id/revoke` (either party, immediate). `PATCH /:id/scopes` owner-only on active connections.
  - **Scoped reads re-verify per request**: `GET /:id/live|alerts|status` each re-check grantee identity, `status === 'active'`, and the specific scope → `403 SCOPE_NOT_GRANTED` (grantee without scope) or `403 CONNECTION_REVOKED` (revoked/pending, immediate). `sos_only` mode gates `location` to active SOS/tracking windows → `403 SOS_ONLY_NO_ACTIVE_WINDOW`.
  - Beacon: `POST /:id/ping` (owner-only) stores into `connection_locations` with a 200-point rolling cap; `GET /:id/live` returns the latest point. Check-in: `POST /:id/checkin` (grantee-only, 1 per 5 min → `429 CHECKIN_RATE_LIMITED`).
  - Frontend `/circle` (`MyCirclePage`, drawer "My Circle (Trusted People)"): copyable Safe ID card, accept/decline incoming requests, scoped live-view bottom sheet (5s poll, honest scope-denied copy), check-in, revoke. Connection client methods in `auth_service.dart` return `{ ok, data }` / `{ ok, code, message }` so UI surfaces the real server error. Safe ID shows in the drawer header.
- **Map Excellence & Movement Intel (M4)**:
  - **24x7 Store category** added to `VALID_MARKER_CATEGORIES` (backend `markerModel.js`) and the submit-marker dropdown; frontend maps it to `Icons.storefront` + `AppColors.green` and a "Stores" filter chip — the always-open-refuge category (cashier, lighting, footfall).
  - **Glowing markers**: `_InteractivePin` renders two stacked category-tinted `BoxShadow` halos so refuges pop on dark tiles at night.
  - **"Near me" service strip**: horizontal strip under the filter chips showing the nearest Police / Hospital / 24x7 / Safe-zone marker with distance, tappable to select on the map. Gated behind `_hasGpsFix` (never rendered against the fabricated Delhi default) and honestly shows "none loaded" for missing categories.
  - **Route guidance line**: selecting a safety marker draws a dashed teal straight-line (`Polyline` + `StrokePattern.dashed`) from the GPS fix to the pin — explicitly documented as NOT turn-by-turn; real routing stays the external directions deep link. Hazards and the user's own pin never get a line.
  - **Movement intel**: `frontend/lib/services/movement_analyzer.dart` — pure-Dart breadcrumb state machine (`unknown | stationary | moving | stalled`) with 120s stall window (F3-2 parity), GPS-jitter threshold (1.5 km/h), dwell-time computation, bogus-gap filtering (skips ≤0s or >1h segments), and heading via Haversine bearing. Summaries are telemetry-only and never claim intent ("safe", "at home"). Surfaced in `TrackSessionPage`'s "Movement" info tile; tolerant to empty/malformed input.
- **Privacy Hub & WhatsApp-first SOS (M5)**:
  - **"Who can see me" privacy hub** (`/privacy-hub`, `PrivacyHubPage`, drawer "Who can see me" — authenticated only): one plain-language surface listing every currently-open visibility channel, all derived from live server data — live tracking sessions (`GET /api/v1/location/sessions/mine`, NEW requireAuth endpoint that **scrubs the tracking token** and returns breadcrumb counts, not payloads), trusted-circle watchers with scopes/mode (instant revoke inline), pending requests ("they can see NOTHING until you accept"), and what's public by default (Safe ID, reports/markers). Honest offline copy ("only shows what's true right now"); Safe ID display tolerant to a null profile.
  - **WhatsApp-first SOS share** (M5): inside the "HELP IS ON THE WAY" hero, a green `Share via WhatsApp` button + generic share chip. `_shareSosViaWhatsApp` pulls a **fresh GPS fix** (never silently reuses stale trigger coordinates), and without a fix sends honest copy ("Could not get GPS fix — call me, do not assume my location"). Uses the universal `wa.me/?text=` scheme with a maps deep link; falls back to the system share sheet when WhatsApp is unavailable.
- **Hardening Sweep (M6)**:
  - **Marker input caps**: `POST /api/v1/markers` now REJECTS (400 `VALIDATION_ERROR`, not truncate) names >80 chars, addresses >200 chars, notes >500 chars.
  - **Offline SOS queue idempotency**: `queueOfflineSos` computes a stable content signature (sorted keys, floats rounded to 4dp) and skips enqueue when an identical non-expired entry already exists — rapid duplicate triggers can't double-dispatch on replay. The signature ignores the `_queuedAt` stamp.
  - **Multi-active-SOS resolve tokens**: resolve tokens persist in a per-alert JSON map (`safesphere_sos_resolve_tokens`, cap 10, oldest evicted) with the legacy single-token key kept in sync for pre-M6 sessions; `resolveSos` reads per-alert first with legacy fallback and prunes on success. A victim with several alerts can self-resolve all of them.
  - **PIN file-fallback hashing**: when FlutterSecureStorage is unavailable, `setPin` writes a salted `sp1$<salt>$<sha256>` hash to file storage (never the raw PIN); `verifyPin` accepts both hashed and legacy plaintext forms, and legacy plaintext file values are upgraded to hashed in place during read-migration. Hash failure degrades gracefully — the user is never locked out.
  - **Tracking credential hygiene**: the `TrackSessionPage` session token lives in memory only — verified never persisted to any storage key; the only egress is the explicit copy-to-clipboard action.

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
| `NOTE:` markers | `frontend/lib/services/auth_service.dart` (register, login, OTP send, OTP verify, PIN verify) | Converted from stale `TODO(REAL_BACKEND)`; endpoints verified live on backend | DONE |
| `AI Assistant (Groq)` | `backend/src/services/aiService.js`, `backend/src/controllers/aiController.js`, `frontend/lib/pages/ai_assistant_page.dart` | `POST /api/v1/ai/chat` (Groq; key via `GROQ_API_KEY` env only), optionalAuth + 10/min `aiLimiter`, sanitized history (12 turns), honest 503 `AI_NOT_CONFIGURED` fallback to offline guides | DONE |
| `Hardening Wave (audit)` | `alertController.js`, `authMiddleware.js`, `validation.js`, `rateLimiter.js`, `config/index.js`, `auth_service.dart` | Guest SOS identity stripping (body identity ignored), optionalAuth + requireAuth session-revocation gates (missing/invalid session ⇒ guest/rejected), dedicated 10/min `otpLimiter` on `/otp/send`+`/otp/verify`, input caps (SOS notes 500 / alertType 40 / report description 2000 / location 200 / coords validated / direct `photoUrl` rejected), env fail-closed (unknown `NODE_ENV` ⇒ production hygiene, incl. inside `validateJwtSecretHygiene`), offline SOS queue 24h TTL with `_queuedAt` stamps | DONE |
| `SMS Gateway (Fast2SMS)` | `backend/src/services/smsGatewayService.js`, `otpService.js`, `sosService.js` | Real SMS delivery via dual providers (`SMS_PROVIDER` env): **fast2sms** (Smart OTP needs DLT template; Quick route ₹7/SMS needs ₹100 top-up) and **textlocal** (10 free credits, no DLT — chosen zero-money demo path; signup must be done in a full browser — the site does not render in embedded webviews). Failed dispatches fail honestly (`502 OTP_DISPATCH_FAILED`). MSG91 was abandoned — its login pipeline is broken. | Adapter DONE — awaiting Textlocal API hash from owner |
| `Maps key` | `frontend/lib/services/map_config.dart` | Google Maps abandoned — Safety Map runs on `flutter_map` + OSM/CARTO tiles, zero key/card; optional MapTiler key via dart-define | DONE (free tier) |
| `TODO(REAL_HARDWARE)` | `frontend/lib/services/auth_service.dart` (`verifyBiometrics`) | Real biometric scan via `local_auth` wired with hardware check and fallback | DONE |
| `TODO(REAL_HARDWARE)` | `frontend/lib/pages/home_page.dart`, `emergency_page.dart` | Volume button / hardware panic intercept requires native plugin, fallback F4-2-alt shipped | DEFERRED |
| `F3-1 (SOS Escalation)` | `backend/src/services/sosService.js`, `frontend/lib/pages/emergency_page.dart` | 60s escalation watchdog, escalationLevel cap 3, WS broadcast, active ageSeconds & badge | DONE |
| `F3-2 (Breadcrumb Stall)` | `backend/src/controllers/locationController.js`, `frontend/lib/pages/track_session_page.dart` | 120s breadcrumb stall detection, 4s polling, amber SIGNAL LOST & Signal restored banners | DONE |
| `F3-3 (Check-in Timer)` | `backend/src/services/trackingService.js`, `frontend/lib/pages/share_location_page.dart` | Dead-man switch (1-1440m), 60s check-in tick, CHECKIN_MISSED WS broadcast, ping reset | DONE |
| `F4-1 (SOS Chat)` | `backend/src/server.js`, `alertController.js`, `frontend/lib/pages/emergency_page.dart` | Two-way WS & REST responder chat, 1 msg/2s rate limit, 50 msg FIFO cap, victim vs responder UI | DONE |
| `M1 Distress-first SOS` | `home_page.dart`, `emergency_page.dart`, `pin_lock_page.dart`, `ai_assistant_page.dart`, `authService.js`, `aiService.js` | SOS-first home (40% viewport hero), elapsed-time countdown ring + huge CANCEL + PopScope guard, plain-language reassurance hero + honest I'm-Safe dialog, forgot-PIN OTP reset (`POST /api/v1/auth/pin/reset`), contacts cap 5 + optional email, connectivity listener + queued-SOS banner, chat quick-replies, AI safety-only guardrails (prompt + client pre-filter) | DONE (home widget deferred — TODO(REAL_HARDWARE)) |
| `M3 Connections (Trusted Circle)` | `backend/src/services/connectionService.js`, `connectionController.js`, `frontend/lib/pages/my_circle_page.dart`, `auth_service.dart`, `userModel.js`, `store.js` | SafeSphere IDs (`SF-XXXX-XX`) at registration, Safe-ID-addressed connection requests (scopes `location|nearby_alerts|sos_status`, mode `always|sos_only`), owner-only accept, either-party instant revoke, per-request scope re-verification (403 on missing scope / revoked), 200-point beacon buffer, 1-per-5-min check-in, `/circle` My Circle UI with live-view sheet | DONE |
| `M4 Map Excellence` | `backend/src/models/markerModel.js`, `frontend/lib/pages/safety_map_page.dart`, `frontend/lib/services/movement_analyzer.dart`, `frontend/lib/pages/track_session_page.dart`, `frontend/test/challenger_m5_map_empirical_test.py` | 24x7 Store category end-to-end, glowing category-tinted marker halos, "Near me" nearest-service strip (GPS-fix gated), dashed straight-line guidance polyline (honest non-turn-by-turn), breadcrumb movement state machine with F3-2 stall parity | DONE |
| `M5 UX Polish` | `backend/src/controllers/locationController.js` (`listMine`), `frontend/lib/pages/privacy_hub_page.dart`, `emergency_page.dart`, `frontend/test/challenger_m6_ux_empirical_test.py` | "Who can see me" privacy hub (live sessions token-scrubbed, watchers, plain-language privacy), WhatsApp-first SOS share with fresh GPS fix + honest no-fix copy + share-sheet fallback | DONE |
| `M6 Hardening Sweep` | `backend/src/controllers/markerController.js`, `frontend/lib/services/auth_service.dart`, `frontend/test/challenger_m7_hardening_empirical_test.py` | Marker name/address/note 400-rejection caps, offline SOS queue content-signature idempotency, per-alert resolve-token map (cap 10 + legacy fallback), PIN file-fallback salted hashing with legacy upgrade, tracking token verified memory-only | DONE |
| `F4-2 (1-Tap SOS)` | `frontend/lib/pages/home_page.dart`, `emergency_page.dart`, `about_page.dart` | Persistent 1-tap SOS action, single countdown gate, lock-screen widget recommendation | DONE |
| `F4-3 (Onboarding & DPDP)` | `frontend/lib/pages/onboarding_page.dart`, `app_drawer.dart`, `backend/src/controllers/authController.js` | 3-screen onboarding, DPDP consent checkbox, emergency bypass, DELETE /api/v1/auth/me wipe | DONE |
| `F4-4 (Review Markers)` | `backend/src/controllers/markerController.js`, `frontend/lib/pages/review_markers_page.dart` | GET /pending, POST /verify with audit fields, admin Review Markers UI | DONE |
| `F4-5 (Report Status)` | `backend/src/controllers/reportController.js`, `frontend/lib/pages/community_alerts_page.dart` | POST /api/v1/reports/:id/status transition, Verified only toggle, status badges | DONE |
| `F5-1 (Hardware Panic Gestures)` | `frontend/lib/services/gesture_service.dart`, `emergency_page.dart` | Volume-down hold & shake-to-SOS listener funneled into SosCountdownDialog | DONE |
| `F5-2 (Accessibility & Distress)` | `frontend/lib/pages/emergency_page.dart`, `theme/app_colors.dart` | High contrast (amber #FFC94D), 64px touch targets, Semantics labels, haptics | DONE |
| `F5-3 (Discreet Fake Call)` | `frontend/lib/pages/fake_call_page.dart`, `auth_state.dart`, `emergency_page.dart` | Realistic incoming call screen, decline/exit, muted SOS visuals toggle | DONE |
| `F5-4 (Report Photos)` | `backend/src/controllers/reportController.js`, `frontend/lib/pages/report_page.dart`, `community_alerts_page.dart` | Base64 photo attachment, 500KB cap, JPEG/PNG validation, thumbnail display | DONE |
| `F5-5 (Citizen Marker Submission)` | `frontend/lib/services/auth_service.dart`, `pages/safety_map_page.dart` | Authenticated safety marker submission FAB & dialog into moderator review queue | DONE |

## Known limitations

- **No SMS gateway.** ~~OTP delivery and emergency-contact SMS are not
  implemented~~ → **DONE via Fast2SMS**: with `SMS_API_KEY` set, login OTPs are
  really delivered (pre-approved route, no DLT needed) and SOS triggers
  dispatch to emergency contacts (Quick route, ₹7/SMS). Without the key the
  old honest no-delivery behavior applies. DLT-registered sender IDs and
  templates are still required for custom-branded SMS beyond Fast2SMS's
  pre-approved templates.
- **Snapshot persistence is single-instance.** The Supabase Storage snapshot
  mode keeps one Render instance durable (same as a persistent disk); it does
  not enable horizontal scaling. Data loss window ≤ one snapshot interval
  (45s default) plus any SIGKILL that bypasses the SIGTERM flush.
- **`dart:io` breaks Flutter web.** `auth_service.dart`, `storage_service.dart`,
  and `share_location_page.dart` use `dart:io` (`HttpClient`, `File`, `WebSocket`).
  This is fine on mobile/desktop but will not compile for the `web` target; use
  `web_preview/` for browser demos.
- **Stale/missing `pubspec.lock` entries.** The lockfile does not list every
  direct dependency (e.g. `geolocator`, `flutter_map`, `local_auth`, `flutter_secure_storage`). Run
  `flutter pub get` on a Flutter-equipped machine before building; do NOT edit `pubspec.lock` by hand.
- **Maps are OSM-based via `flutter_map`** — no API key, no card, no billing
  account. The Safety Map renders CARTO dark raster tiles (OSM data) with an
  OSM attribution; a free MapTiler key can be passed at build time via
  `--dart-define=SAFESPHERE_MAP_TILER_KEY=<key>` to upgrade tiles. The former
  `google_maps_flutter` dependency was removed (it was never imported and its
  SDK required a billing-verified Google Cloud account).
- **AI assistant requires `GROQ_API_KEY`.** Without it `POST /api/v1/ai/chat`
  returns an honest `503 AI_NOT_CONFIGURED` and the UI falls back to the
  offline safety guides. The key is never committed or returned to clients.
- Duplicate export shims (`lib/pages/login_page.dart`, `signup_page.dart`,
  `auth_pin_page.dart`) re-export the real pages under `lib/pages/auth/` and must
  be kept for compatibility with the structural verifier.

## Testing & verification

```bash
# Full gate (recommended)
npm test

# Backend only — 334 tests across 82 suites
cd backend && npm test
npm run smoke

# Individual backend suites
cd backend
node --test tests/report_photo.test.js        # F5-4 report photo attachments & base64 cap
node --test tests/sos_chat.test.js            # F4-1 two-way SOS chat & rate limiting
node --test tests/sos_escalation.test.js      # F3-1 SOS auto-escalation & watchdog
node --test tests/tracking_stall.test.js      # F3-2 breadcrumb-stall detection
node --test tests/tracking_checkin.test.js    # F3-3 check-in timer dead-man switch
node --test tests/connections.test.js         # M3 trusted circle: Safe IDs, scopes, revoke, beacons, check-in
node --test tests/privacy_hub.test.js         # M5 privacy hub: sessions/mine auth + token scrub
node --test tests/location_tracking.test.js   # live tracking + token gating
node --test tests/auth.test.js
node --test tests/security_hardening.test.js
node --test tests/reports_markers.test.js
node --test tests/ai_chat.test.js             # AI assistant Groq chat, validation & honest fallback
node --test tests/db_snapshot.test.js         # Supabase snapshot persistence, hydrate fail-safe & pruning
node --test tests/hardening.test.js           # guest SOS identity stripping, revocation gates, input caps, OTP limiter, env fail-closed
node --test tests/sms_gateway.test.js         # Fast2SMS SMS gateway: OTP dispatch, SOS contacts, honest failures

# Python challengers (197 tests across 10 suites: frontend structure, routes, AST invariants, permissions)
python -m unittest discover -s frontend/test -p "*.py"
python frontend/test/adversarial_r1_challenger_test.py
python frontend/test/challenger_m2_empirical_test.py
python frontend/test/test_r5_permissions_contrast.py
```

All of the above must pass before considering a change complete. Commit per logical fix
and push to origin/main as authorized.
