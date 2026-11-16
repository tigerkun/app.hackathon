---
name: safesphere-fullstack-workflow
description: >-
  Authoritative developer runbook and architectural guide for SafeSphere emergency response platform.
  Covers full-stack development workflows, Node.js and Flutter test harnesses, multi-modal auth,
  offline-first emergency invariants, live telemetry streaming, and production security patterns.
---

# SafeSphere Full-Stack Engineering, Architecture & Verification Runbook

## Overview & Mission Invariant

SafeSphere is an enterprise-grade emergency response and public safety platform designed for rapid distress broadcasting, multi-modal authentication, continuous guardian tracking, and verified community incident reporting. 

The system operates across three tiers:
1. **Frontend Client**: Cross-platform Flutter application (`frontend/lib`) backed by a lightweight standalone HTML5 web preview server (`frontend/web_preview`).
2. **Backend Service**: High-throughput Node.js/Express service (`backend/src`) supporting REST APIs and persistent WebSocket pub/sub telemetry (`/ws/sos`).
3. **Automated Verification Harness**: Multi-tiered test suite executing native Node.js integration tests, static AST route audits, and Python adversarial challenger simulations.

---

## 1. Architecture Blueprint & System Topology

### 1.1 Monorepo Directory Topology

SafeSphere is structured as a unified monorepo enabling synchronized client-server evolution, cross-platform automation, and zero-drift API contracts:

```text
safesphere/
├── backend/                        # Node.js / Express REST & WebSocket API Service
│   ├── package.json                # Dependencies: express, ws, jsonwebtoken, bcryptjs, cors
│   ├── src/
│   │   ├── server.js               # HTTP & WebSocket server boot, room router, ping/pong heartbeats
│   │   ├── app.js                  # Express middleware pipeline, rate limiting, error envelopes
│   │   ├── config/
│   │   │   └── index.js            # Centralized config, JWT hygiene validation, demo mode gating
│   │   ├── controllers/            # Request handlers (auth, alert, marker, report, location)
│   │   ├── services/               # Business logic (auth, token, otp, geo, sos, tracking)
│   │   ├── middleware/             # authMiddleware, validation, rateLimiter, errorHandler
│   │   ├── models/                 # userModel, sessionModel, alertModel, markerModel, reportModel, trackingModel
│   │   └── data/
│   │       ├── store.js            # Thread-safe in-memory DataStore with instant reset() isolation
│   │       └── seedData.js         # Demo seed entities and Delhi NCR safety markers
│   └── tests/                      # Native Node.js test suites (108+ unit, integration & stress tests)
│       ├── helpers/testApp.js      # Ephemeral test server harness (port 0) with db.reset() isolation
│       ├── auth.test.js            # Multi-modal auth, PIN login, OTP, and token refresh
│       ├── security_hardening.test.js # Bcrypt PIN hashing, demo gating, JWT hygiene
│       ├── challenger_m2_adversarial.test.js   # Adversarial security & boundary stress tests
│       ├── challenger_m2_2_adversarial.test.js # Telemetry, WebSocket, reports & marker stress
│       ├── location_tracking.test.js           # Live guardian tracking rooms & REST pings
│       └── reports_markers.test.js             # Crowdsourced hazards & Haversine proximity
├── frontend/                       # Flutter Mobile Client & Web Preview
│   ├── pubspec.yaml                # Flutter project manifest & asset declarations
│   ├── lib/
│   │   ├── main.dart               # App entrypoint; declares _appRouteMap for static analyzers
│   │   ├── routes/
│   │   │   ├── app_routes.dart     # Canonical route name constants
│   │   │   └── route_guard.dart    # Unconditional emergency bypass & PIN lock security barrier
│   │   ├── data/
│   │   │   ├── auth_state.dart     # Reactive ChangeNotifier tracking user, session, and PIN lock
│   │   │   └── report_store.dart   # In-memory incident store with cached O(1) status queries
│   │   ├── services/
│   │   │   ├── auth_service.dart   # Backend REST client for authentication and session refresh
│   │   │   ├── storage_service.dart # IStorageService with platform disk persistence & memory fallback
│   │   │   └── map_config.dart     # Map provider and tile configuration
│   │   ├── pages/                  # 12 core screens (auth, emergency dialer, map, radar, tracker)
│   │   └── widgets/                # Reusable UI widgets (AppDrawer, GlassContainer, TypingText)
│   ├── test/                       # Python challenger & AST regression harnesses
│   │   ├── adversarial_r1_challenger_test.py # Route security, AST imports, and dialer invariant
│   │   ├── challenger_m2_empirical_test.py   # Navigation stack stress & unknown route fallback
│   │   └── test_r5_permissions_contrast.py  # Runtime permission matrix & contrast tests
│   └── web_preview/                # Standalone HTML5 web preview (runs on port 8080)
│       ├── server.js               # Zero-dependency HTTP static server
│       └── index.html              # Interactive mobile viewport simulator
├── scripts/                        # Monorepo Automation Scripts
│   ├── dev.js                      # Concurrent runner spawning backend and web preview
│   ├── test.js                     # Unified verification runner (Dart audit + Node + Python)
│   └── clean.js                    # Cross-platform cache and build artifact cleaner
├── docs/                           # Architecture, API specifications, and PRD
└── package.json                    # Monorepo root workspace orchestrator
```

### 1.2 Layered Backend Architecture

The backend strictly enforces a unidirectional five-tier architecture pattern:

```text
[ Client / Web Browser / Mobile App ]
                 │
                 ▼  (HTTP / WebSocket)
┌─────────────────────────────────────────────────────────┐
│ 1. Routing & Middleware Layer                           │
│    - Global & Auth Sliding-Window Rate Limiters         │
│    - JSON Body Parser (10MB payload ceiling)            │
│    - Payload Validation (validation.js)                 │
│    - Authentication (authMiddleware: Bearer HS256)      │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Controller Layer (src/controllers/*)                 │
│    - Extracts parameters, query strings, headers        │
│    - Formats standard REST envelopes: { success, data } │
│    - Maps uncaught domain errors to standard HTTP codes │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Service Layer (src/services/*)                       │
│    - Pure domain logic & business validation rules      │
│    - Bcrypt credential hashing & comparison             │
│    - Cryptographic OTP generation (crypto.randomInt)    │
│    - Great-circle Haversine distance math               │
│    - WebSocket broadcast dispatch                       │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Model Layer (src/models/*)                           │
│    - Entity constructors with default timestamping      │
│    - Schema sanitizers (toSafeUser: strips hashes/PINs) │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│ 5. DataStore Layer (src/data/store.js)                  │
│    - In-memory thread-safe Maps with indexed lookups    │
│    - Collections: users, sessions, reports, markers,   │
│      alerts, otps, trackingSessions                     │
│    - Instant reset() (<1ms) providing test isolation    │
└─────────────────────────────────────────────────────────┘
```

### 1.3 Dual-Token JWT Lifecycle & Session Revocation

Authentication utilizes an asymmetric dual-token JWT rotation strategy:
- **Access Token**:
  - Signed with `JWT_SECRET` using `HS256`.
  - Short-lived: 15 minutes (`900` seconds).
  - Sent in HTTP request header: `Authorization: Bearer <accessToken>`.
  - Stateless verification in `authMiddleware.requireAuth` verifying signature and checking `user.isActive`.
- **Refresh Token**:
  - Signed with `JWT_REFRESH_SECRET` using `HS256`.
  - Long-lived: 7 days (`604800` seconds).
  - Tracked in `DataStore.sessions` map keyed by session ID with `userId`, `isValid`, and `expiresAt`.
- **Rotation on `/api/v1/auth/refresh`**:
  - Verifies signature against `JWT_REFRESH_SECRET`. Cross-contamination defense ensures access tokens signed with `JWT_SECRET` are rejected immediately.
  - Queries session in `DataStore`; verifies `session.isValid === true` and `session.expiresAt > Date.now()`.
  - Atomically invalidates old session and issues fresh access and refresh token pair.
- **Instant Revocation on `/api/v1/auth/logout`**:
  - Sets `session.isValid = false` in `DataStore`. Any subsequent presentation of that refresh token or session is rejected with `401 Unauthorized` (`SESSION_REVOKED`).

### 1.4 In-Memory Thread-Safe DataStore & Test Isolation

`backend/src/data/store.js` implements a high-performance in-memory database using JavaScript `Map` structures:
- Fast O(1) primary key indexing on entity IDs.
- Secondary indexes and lookup helpers (e.g. `findUserByEmail`, `findUserByPhone`, `findActiveTrackingSession`).
- Instant boot time (< 15ms) without external database dependencies (SQLite/PostgreSQL).
- `db.reset(options)` method clears all collections and re-populates seed data:
  - If `options.demoMode` (or `config.isDemoMode`) is true, seeds `demoUser` (`demo@safesphere.org`).
  - If `options.demoMode` is false (production mode), demo user seeding is completely bypassed.
  - Public Delhi NCR safety markers and baseline incident reports remain seeded for operational realism.

---

## 2. Developer Workflows & Automation

### 2.1 Prerequisites

Ensure the following runtimes are installed and present on your environment `$PATH`:
- **Node.js**: Version `>= 18.0.0` (LTS recommended)
- **Python**: Version `>= 3.10` (Standard library only; zero pip package dependencies)
- **Flutter SDK** (Optional): Version `>= 3.19.0` for native mobile APK/iOS compilation. Zero Flutter dependencies are required to run tests or the web preview.

### 2.2 Monorepo Automation Scripts

Run all development commands from the monorepo root directory:

| Command | Action | Implementation | Port(s) |
|---|---|---|---|
| `npm run dev` | Spawns backend API and web preview concurrently with clean shutdown | `node scripts/dev.js` | 3000 (API), 8080 (Web) |
| `npm run backend` | Boots the Node.js / Express backend service | `npm --prefix backend start` | 3000 |
| `npm run backend:dev` | Runs backend in development mode | `npm --prefix backend run dev` | 3000 |
| `npm run frontend:preview` | Boots the zero-dependency HTML5 web preview server | `node frontend/web_preview/server.js` | 8080 |
| `npm test` | Executes unified monorepo verification harness | `node scripts/test.js` | Ephemeral (port 0) |
| `npm run test:backend` | Runs the backend native Node.js test suite | `npm --prefix backend test` | Ephemeral (port 0) |
| `npm run clean` | Cleans build caches, `.dart_tool`, `coverage`, and Python bytecode | `node scripts/clean.js` | N/A |

### 2.3 Concurrent Dev Server Mechanics (`scripts/dev.js`)

`scripts/dev.js` provides cross-platform execution:
- Spawns backend on port `3000` (`http://127.0.0.1:3000`).
- Spawns frontend preview on port `8080` (`http://127.0.0.1:8080`).
- Registers `SIGINT`, `SIGTERM`, and `exit` process hooks.
- On Windows, uses `taskkill /pid <PID> /T /F` to terminate process trees cleanly without orphaned port bindings; on POSIX systems, sends `SIGTERM`.

### 2.4 Environment Variables Specification

Configure runtime behavior via `.env` or system environment variables:

| Variable | Type | Default (Dev) | Production Requirement | Purpose |
|---|---|---|---|---|
| `PORT` | Integer | `3000` | Optional (default 3000 or platform provided) | HTTP & WebSocket listening port |
| `NODE_ENV` | String | `'development'` | Must be `'production'` | Runtime mode; controls error masking and gating |
| `JWT_SECRET` | String | `'safesphere_dev_jwt_secret_key_2026_super_secure'` | **MANDATORY**: Min 32 chars, cryptographic, not in denylist | Signing secret for 15-minute access tokens |
| `JWT_REFRESH_SECRET` | String | `'safesphere_dev_jwt_refresh_secret_key_2026_super_secure'` | **MANDATORY**: Min 32 chars, must NOT equal `JWT_SECRET` | Signing secret for 7-day refresh tokens |
| `SALT_ROUNDS` | Integer | `8` (test), `10` (dev/prod) | `10` to `12` | Bcrypt hashing cost factor for passwords & PINs |
| `DEMO_MODE` | Boolean | `'true'` in dev | Must be `'false'` in production | Controls seeding of demo credentials (`demo@safesphere.org`) |
| `CORS_ORIGIN` | String | `'*'` | Domain whitelist (e.g. `'https://app.safesphere.org'`) | Cross-Origin Resource Sharing whitelist |

---

## 3. Verification & Test Harness Runbook

SafeSphere enforces automated test verification across all tiers with zero mock bypasses.

### 3.1 Backend Native Test Runner

The backend uses Node.js's native test runner (`node:test` and `node:assert`), eliminating dependencies on Jest or Mocha:

```bash
# From monorepo root:
npm run test:backend

# Or directly inside the backend directory:
cd backend
node --test tests/**/*.test.js
```

**Expected Baseline**: 108+ passing tests, 29+ test suites, 0 failures, executing in < 2.5 seconds.

### 3.2 Ephemeral Test Server Architecture (`testApp.js`)

All integration test suites boot an isolated HTTP server using `backend/tests/helpers/testApp.js`:
```javascript
const { startTestServer } = require('./helpers/testApp');

describe('Feature Test Suite', () => {
  let app;

  before(async () => {
    // Boots Express on port 0 (OS assigns available ephemeral port)
    // Automatically runs db.reset() and sets NODE_ENV = 'test'
    app = await startTestServer();
  });

  after(async () => {
    await app.close();
  });

  it('demonstrates zero port collision', async () => {
    const res = await app.request('/api/v1/markers');
    assert.strictEqual(res.status, 200);
  });
});
```
**Benefits**:
- **Zero Port Collisions**: Ephemeral port `0` ensures multiple test suites or parallel CI workers never collide on port 3000.
- **Hermetic State**: `db.reset()` runs prior to server listen, ensuring clean collections for each suite.
- **Convenience Client**: `app.request(path, options)` wraps Node's native `fetch` with automatic JSON serialization and deserialization.

### 3.3 Running Specific Backend Test Suites

Execute isolated suites for rapid feedback:

```bash
cd backend

# 1. Multi-modal authentication & session tests (21 tests)
node --test tests/auth.test.js

# 2. Production security hardening (PIN bcrypt, demo gating, JWT hygiene)
node --test tests/security_hardening.test.js

# 3. Adversarial stress & timing-safe envelope tests (23 tests)
node --test tests/challenger_m2_adversarial.test.js

# 4. Telemetry, WebSocket, reports & marker tests (41 tests)
node --test tests/challenger_m2_2_adversarial.test.js

# 5. Live guardian tracking & WebSocket stream tests (11 tests)
node --test tests/location_tracking.test.js

# 6. Incident reports & Haversine proximity tests (6 tests)
node --test tests/reports_markers.test.js
```

### 3.4 Python Challenger Test Suites

SafeSphere includes independent Python test suites that inspect client AST structure, route stability, and permission policies:

```bash
# Execute individual challenger tests from monorepo root:
python frontend/test/adversarial_r1_challenger_test.py
python frontend/test/challenger_m2_empirical_test.py
python frontend/test/test_r5_permissions_contrast.py
```

1. **`adversarial_r1_challenger_test.py`** (16 tests):
   - AST parsing of `frontend/lib/main.dart` and `route_guard.dart`.
   - Asserts coexistence of static `_appRouteMap` table (for static analysis) with runtime `RouteGuard.generateRoute`.
   - Asserts emergency dialer invariant: verifies `tel:112` and `tel:181` are present and reachable without authentication.
2. **`challenger_m2_empirical_test.py`** (12 tests):
   - Navigation stack simulation (1000 random-walk push/pop operations).
   - Unknown route fallback: feeds adversarial strings (empty string, emojis, SQLi strings) to `onUnknownRoute` and confirms safe fallback to `HomePage`.
   - Verifies legacy aliases (`/community` -> `/alerts`, `/chat` -> `/assistant`).
3. **`test_r5_permissions_contrast.py`** (7 tests):
   - Verifies runtime permissions boundaries for GPS, camera, and microphone across distress workflows.

### 3.5 Unified Monorepo Runner (`node scripts/test.js`)

Run the complete monorepo gate check with one command:
```bash
npm test
# Or:
node scripts/test.js
```
The script executes in 3 sequential steps:
1. **Step 1 (Frontend Structural Integrity)**:
   - Validates existence of 38 required manifest, service, route, and widget files.
   - Verifies minimum 24 active Dart files in `frontend/lib` (currently 33).
   - Audits all relative Dart imports (65 imports audited) to confirm 0 broken paths.
2. **Step 2 (Backend Test Suite)**:
   - Spawns `npm --prefix backend test` and verifies exit code 0 across all 108+ tests.
3. **Step 3 (Python Adversarial Suites)**:
   - Runs all Python challenger test files in sequence and checks for 100% clean passes.
   - Exits with `0` on total success or `1` if any check fails.

---

## 4. Core Architectural Patterns & Invariants

### 4.1 The Unconditional Emergency Invariant

> **CRITICAL ARCHITECTURAL INVARIANT**:
> Route guards, authentication layers, PIN barriers, and network latency must **NEVER** block or delay emergency dialers (`tel:112`, `tel:181`) or distress broadcast sharing.

In `frontend/lib/routes/route_guard.dart`:
```dart
class RouteGuard {
  static Route<dynamic> generateRoute(RouteSettings settings, AuthState authState) {
    final String routeName = settings.name ?? AppRoutes.home;

    // 1. INVARIANT EMERGENCY BYPASS:
    // Routes /emergency and /share are NEVER blocked by auth status or PIN lock.
    if (routeName == AppRoutes.emergency || routeName == AppRoutes.shareLocation) {
      return MaterialPageRoute(
        builder: (_) => _resolveEmergencyPage(routeName),
        settings: settings,
      );
    }

    // 2. PIN Lock Barrier (enforced only for non-emergency routes)
    if (authState.isPinLocked && routeName != AppRoutes.login) {
      return MaterialPageRoute(
        builder: (_) => const PinLockPage(),
        settings: settings,
      );
    }
    
    // ... remaining auth & protected routes
  }
}
```

**Prohibited Anti-Patterns**:
- ❌ Requiring valid JWT access token to view or dial emergency contacts (`/emergency`).
- ❌ Forcing biometric or PIN re-entry before opening distress sharing (`/share`).
- ❌ Using inert UI callbacks (`onPressed: () {}`) on emergency triggers.
- ❌ Introducing network roundtrips before displaying native dialer action sheets.

### 4.2 Offline-First Resilience & Storage Fallback

The mobile client implements the `IStorageService` interface (`frontend/lib/services/storage_service.dart`):
- Persists session credentials, active tracking tokens, and emergency settings to disk at `${getApplicationDocumentsDirectory()}/safesphere/user_session_store.json`.
- Automatically catches file system and permission exceptions, falling back seamlessly to an in-memory `Map<String, String>` store.
- Guarantees the application remains interactive and can dial local emergency dispatchers even if device storage is full, corrupted, or unavailable.

### 4.3 Production Security Hardening

SafeSphere backend enforces production security controls:

#### 1. Bcrypt PIN and Password Hashing
- Citizen accounts support rapid emergency unlocking via a 4-to-6 digit numeric PIN.
- On user registration (`POST /api/v1/auth/register`), if a PIN is provided, it is hashed with bcrypt:
  ```javascript
  const pinHash = bcrypt.hashSync(String(pin).trim(), config.saltRounds);
  ```
- On PIN login (`POST /api/v1/auth/login-pin`), verification compares the plaintext candidate against the stored hash:
  ```javascript
  const isMatch = bcrypt.compareSync(String(pin).trim(), storedPin);
  ```
- Entity sanitization (`toSafeUser(user)`) exposes only `hasPin: Boolean(user.pin || user.pinHash)` and **NEVER** leaks `passwordHash`, `pin`, or `pinHash` across API responses.

#### 2. Demo Account Seed Gating (`isDemoMode`)
- `backend/src/config/index.js` computes:
  ```javascript
  config.isDemoMode = process.env.DEMO_MODE !== undefined 
    ? (process.env.DEMO_MODE === 'true' || process.env.DEMO_MODE === '1')
    : (process.env.NODE_ENV !== 'production');
  ```
- `DataStore.reset()` checks `shouldSeedDemo`: in production (`NODE_ENV === 'production'`) or when `DEMO_MODE=false`, demo user credentials (`demo@safesphere.org` / `SafeSphere@2026`) are completely omitted from memory.
- Public Delhi NCR markers and baseline safety zones remain available for navigation.

#### 3. JWT Secret Hygiene Validation
- The backend validates secret configuration on startup via `validateJwtSecretHygiene`:
  - **Production Requirement**: When `NODE_ENV === 'production'`, `JWT_SECRET` and `JWT_REFRESH_SECRET` must be set via environment variables.
  - **Denylist Rejection**: Insecure defaults (e.g. `'safesphere_dev_jwt_secret_key_2026_super_secure'`, `'secret'`, `'password'`, `'change_me'`) throw a fatal `INSECURE_JWT_CONFIG` error.
  - **Minimum Length**: Secrets must be at least 32 characters in length.
  - **Secret Distinctness**: `JWT_SECRET` and `JWT_REFRESH_SECRET` must not be identical, preventing token cross-contamination.

#### 4. Sliding-Window Rate Limiters
`backend/src/middleware/rateLimiter.js` protects API availability:
- **Global Limiter**: 100 requests per minute per IP.
- **Auth Limiter**: 10 requests per minute per IP on credential-sensitive endpoints (`/login`, `/register`, `/login-pin`, `/otp/*`).
- Standard compliance: Returns headers `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, and `Retry-After` with HTTP `429 Too Many Requests`.

---

## 5. Real-Time Telemetry & Geolocation

### 5.1 Real-Time SOS Streaming on `/ws/sos`

The backend WebSocket server operates at path `/ws/sos` alongside the HTTP server:
- **Client Management**: Maintains active connections in a `clients` Set and attaches heartbeat state (`isAlive = true`).
- **Ping / Pong Heartbeat**: Sends WebSocket ping every 30 seconds (`setInterval` marked with `.unref()` so it does not block process exit); terminates unresponsive sockets.
- **Distress Broadcast**: When an SOS is triggered via `POST /api/v1/sos/trigger`, `broadcastSosAlert` immediately relays the payload to all connected clients:
  ```json
  {
    "type": "SOS_ALERT_BROADCAST",
    "alert": {
      "id": "alt_1710600000_a1b2c3d4",
      "userId": "usr_citizen_01",
      "latitude": 28.6139,
      "longitude": 77.2090,
      "status": "ACTIVE",
      "triggeredAt": "2026-11-16T19:30:00.000Z"
    },
    "timestamp": "2026-11-16T19:30:00.000Z"
  }
  ```

### 5.2 Live Guardian Tracking Rooms

SafeSphere enables time-bounded live location sharing between distress broadcasters and designated guardians:

```text
Broadcaster (Citizen)             WebSocket Server (/ws/sos)              Guardians
      │                                       │                               │
      ├─────── POST /location/share-session ─>│                               │
      │        (creates session & token)      │                               │
      │<────── returns { sessionId, token } ──┤                               │
      │                                       │<── SUBSCRIBE_TRACKING ────────┤
      │                                       │    { sessionId }              │
      │                                       ├─── SUBSCRIBED_TRACKING ──────>│
      │                                       ├─── TRACKING_SNAPSHOT ────────>│
      │                                       │    (historical breadcrumbs)   │
      ├─────── LOCATION_STREAM_UPDATE ───────>│                               │
      │        { lat, lon, speed, battery }   ├─── LOCATION_STREAM_UPDATE ───>│
      │                                       │    (relayed in real-time)     │
      ├─────── STREAM_TERMINATE ─────────────>│                               │
      │        { sessionId, reason }          ├─── STREAM_TERMINATE ─────────>│
```

1. **Session Creation**:
   - `POST /api/v1/location/share-session` generates a tracking session with a unique `shareToken`, expiry time (default 60 minutes), and initial coordinates.
2. **Room Subscription**:
   - Guardian connects to `/ws/sos` and sends:
     ```json
     { "type": "SUBSCRIBE_TRACKING", "sessionId": "tr_1710600000_e5f6" }
     ```
   - Server registers socket in `trackingRooms.get(sessionId)` and sends existing breadcrumb snapshot.
3. **Telemetry Streaming**:
   - Broadcaster streams location updates via WebSocket message:
     ```json
     {
       "type": "LOCATION_STREAM_UPDATE",
       "sessionId": "tr_1710600000_e5f6",
       "latitude": 28.6145,
       "longitude": 77.2095,
       "speed": 1.2,
       "battery": 85,
       "accuracy": 4.5,
       "timestamp": "2026-11-16T19:31:00.000Z"
     }
     ```
   - Server persists breadcrumb via `trackingService.recordPing` and broadcasts to all room subscribers. Alternatively, clients without WebSocket support can push pings via REST `POST /api/v1/location/ping`.
4. **Session Termination**:
   - Broadcaster sends `{ "type": "STREAM_TERMINATE", "sessionId": "...", "reason": "Arrived safely" }`.
   - Server marks session inactive and broadcasts `STREAM_TERMINATE` to all guardians before closing room.

### 5.3 Haversine Proximity Calculations (`/api/v1/markers/nearby`)

SafeSphere calculates great-circle spherical distance using the Haversine formula (`backend/src/services/geoService.js`):
```javascript
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371.0; // Earth mean radius in kilometers
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
      Math.cos(lat2 * (Math.PI / 180)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 1000) / 1000; // Returns km rounded to 3 decimal places
}
```

**API Query**:
`GET /api/v1/markers/nearby?latitude=28.6139&longitude=77.2090&radius=10&category=police`
- Validates latitude (`-90` to `90`) and longitude (`-180` to `180`).
- Filters markers matching the category (e.g. `police`, `hospital`, `safe_zone`).
- Sorts markers by `distanceKm` in ascending order.

---

## 6. Developer Guidelines & Anti-Patterns

### 6.1 Strict Prohibitions

1. **NO Git Commits or Pushes**: All work in this environment is local-only. Never run `git commit` or `git push`.
2. **NO Hardcoded Mock Tokens**: Never use dummy JWT strings (e.g. `'mock_token_xyz'`) or hardcoded bypass OTPs (`'123456'`) in production code.
3. **NO Inert Emergency Handlers**: Emergency buttons must connect directly to native dialers or distress services; never use empty lambdas `() {}`.
4. **NO Cleartext PIN Storage**: PINs must always be hashed with bcrypt prior to storage in database or session models.
5. **NO Production Fallback Secrets**: Production configurations must fail fast if `JWT_SECRET` is unset or matches denylisted development strings.

### 6.2 Pre-Pull-Request Checklist

Before submitting code modifications:
- [ ] Run `npm run clean` to remove stray caches and test artifacts.
- [ ] Run `npm run test:backend` — confirm all 108+ tests pass with 0 failures.
- [ ] Run `python frontend/test/adversarial_r1_challenger_test.py` — verify route AST and emergency dialer invariant.
- [ ] Run `python frontend/test/challenger_m2_empirical_test.py` — verify navigation stack and fallback handling.
- [ ] Run `python frontend/test/test_r5_permissions_contrast.py` — verify permissions boundary.
- [ ] Run `npm test` (`node scripts/test.js`) — ensure complete unified monorepo verification exits with code 0.
