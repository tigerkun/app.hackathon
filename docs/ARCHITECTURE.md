# SafeSphere — System Architecture Specification

**Document Version**: 3.0.0-ENTERPRISE  
**Project**: SafeSphere Monorepo  
**Status**: APPROVED & ACTIVE  
**Last Updated**: October 2026  

---

## 1. Architectural Overview & Design Principles

SafeSphere is architected as an enterprise-grade monorepo cleanly partitioning the **Client Presentation Tier** (`frontend/`), the **Application & Telemetry Tier** (`backend/`), **Shared Contracts** (`shared/`), and **Documentation & Automation** (`docs/`, `scripts/`).

```
+-----------------------------------------------------------------------------------------+
|                                    SAFESPHERE MONOREPO                                  |
+-----------------------------------------------------------------------------------------+
       |                                       |                                    |
       v                                       v                                    v
+------------------+                 +--------------------+                 +---------------+
|    frontend/     |                 |      backend/      |                 |    shared/    |
| (Flutter Mobile, | <============== |  (Node.js Express  | <============== | (OpenAPI 3.0, |
|  Web & Desktop)  |   REST & WSS    |  & WebSocket API)  |     Contracts   |  JSON Types)  |
+------------------+                 +--------------------+                 +---------------+
       |                                       |                                    |
       +-------------------+-------------------+------------------------------------+
                           |
                           v
                 +-------------------+
                 |  Root Automation  |
                 | (scripts/dev.js,  |
                 |  test.js, clean)  |
                 +-------------------+
```

### Core Design Principles
1. **Unconditional Emergency Invariant**: Emergency dialers (`tel:112`, `tel:181`) and distress location sharing must NEVER be blocked behind network availability, authentication walls, or database latency.
2. **Layered Separation of Concerns**: Controllers handle request parsing and response envelopes; Services encapsulate business logic; Middleware enforces security, rate limiting, and validation; Models define entities and sanitize data.
3. **Cross-Platform Zero-Dependency Automation**: Monorepo scripts (`scripts/dev.js`, `scripts/test.js`, `scripts/clean.js`) run across Windows, macOS, and Linux without requiring external bash dependencies.
4. **Event-Driven Telemetry & Cryptographic Privacy**: Zero background ambient tracking. Coordinates are processed strictly during active user-initiated distress sessions, with all telemetry streams protected by end-to-end encryption.

---

## 2. Monorepo Directory Topology

```
safesphere/
├── package.json               # Root monorepo orchestrator (npm run dev, test, clean)
├── README.md                  # Developer quickstart and project overview
├── .gitignore                 # Unified gitignore across Flutter, Node, SQLite, env
├── scripts/                   # Cross-platform zero-dependency automation scripts
│   ├── dev.js                 # Concurrent frontend web preview & backend runner
│   ├── test.js                # Monorepo structural and automated test runner
│   └── clean.js               # Multi-tier cache and artifact cleanup script
├── frontend/                  # Standalone Flutter application
│   ├── pubspec.yaml           # Flutter dependencies (geolocator, url_launcher, etc.)
│   ├── lib/
│   │   ├── main.dart          # App entrypoint with AuthState and RouteGuard
│   │   ├── routes/            # AppRoutes and RouteGuard with emergency bypass
│   │   ├── models/            # UserModel, AuthTokens, ReportModel, SafetyMarker
│   │   ├── services/          # AuthService, StorageService, MapConfig
│   │   ├── data/              # AuthState (ChangeNotifier), ReportStore
│   │   ├── pages/             # Core screens (Home, Emergency, Report, Map, etc.)
│   │   │   └── auth/          # LoginPage, RegisterPage, PhoneOtpPage, PinLockPage
│   │   └── widgets/           # AppDrawer, GlassContainer, MapPlaceholder, TypingText
│   ├── android/ ios/ web/     # Native platform embedding targets
│   ├── test/                  # Flutter unit, widget, and adversarial challenger tests
│   └── web_preview/           # Zero-install HTML5/ES6 interactive preview portal
├── backend/                   # Dedicated Node.js Express REST & WebSocket API
│   ├── package.json           # Backend dependencies (express, ws, bcryptjs, jsonwebtoken)
│   ├── src/
│   │   ├── app.js             # Express application configuration & middleware stack
│   │   ├── server.js          # HTTP server & WebSocket (/ws/sos) stream bootstrap
│   │   ├── controllers/       # authController, reportController, markerController, etc.
│   │   ├── services/          # authService, tokenService, otpService, geoService
│   │   ├── routes/            # Modular Express routers mounted under /api/v1
│   │   ├── middleware/        # authMiddleware, validation, rateLimiter, errorHandler
│   │   ├── models/            # userModel, sessionModel, reportModel, markerModel, alertModel
│   │   └── data/              # store.js (in-memory & SQLite data store), seedData.js
│   └── tests/                 # Node.js automated test runner (node:test)
├── shared/                    # Cross-tier interface contracts
│   ├── contracts/             # OpenAPI contracts (api_contracts.json)
│   └── types/                 # Shared JSON schemas and TypeScript definitions
└── docs/                      # Central Documentation Hub
    ├── ARCHITECTURE.md        # This system architecture specification
    ├── API_SPEC.md            # REST and WebSocket endpoint specifications
    └── PRD.md                 # Master product requirements document (All 8 sections)
```

---

## 3. Frontend Architecture (`frontend/`)

### 3.1 State Management & Reactive Store
- **`AuthState` (`ChangeNotifier`)**: Pure-Dart reactive authentication store managing:
  - `status`: `initial`, `unauthenticated`, `guest`, `authenticated`, `pinLocked`, `otpPending`, `loading`.
  - `currentUser`: Holds active `UserModel` instance or `UserModel.guest()`.
  - `tokens`: Access and refresh tokens persisted via `IStorageService`.
- **`StorageService` (`IStorageService`)**: Abstraction over persistent local storage with graceful in-memory fallback for testing, CI pipelines, and web environments.

### 3.2 Invariant Route Guards & Emergency Bypass
- **`RouteGuard.generateRoute`**: Evaluates all navigation requests:
  1. **Unconditional Emergency Bypass**: Routes `/emergency` and `/share` are NEVER blocked by auth guards, PIN locks, or loading states.
  2. **PIN Lock Gate**: When `authState.isPinLocked` is true, routes redirect to `/pin-lock` while preserving emergency bypass.
  3. **Guest Fallback**: Allows unauthenticated citizens to view `/home`, `/safety-map`, and `/alerts` in read-only mode.

### 3.3 Dynamic `AppDrawer` Integration
- The navigation drawer dynamically reacts to `AuthState`:
  - **Authenticated State**: Renders verified avatar, full name, phone, emergency contact summary, session chip, and a prominent "Logout" CTA.
  - **Guest State**: Renders guest shield badge with a "Sign In / Setup PIN" CTA.
  - **Direct Destinations**: Wires access to Home, Emergency, Report, Safety Map, Share Location, Watch Live Trip (`/track`), Community Alerts, and About.

### 3.4 Hardware-Backed Secure PIN Storage & Offline Queuing
- **Hardware-Backed PIN (`safesphere_user_pin`)**: Authentication PINs are stored securely using `FlutterSecureStorage` (backed by Android KeyStore / iOS Keychain). On first launch, the service automatically detects and migrates legacy unencrypted file storage entries (`keyPin`) into secure storage and deletes the unencrypted entry. If platform channels throw (e.g. desktop/web runners or headless test suites), it gracefully falls back to local file storage so citizens are never locked out of emergency services.
- **Offline SOS Queue (`safesphere_offline_sos_queue`)**: Distress alerts triggered when offline are safely queued in local storage (capped at 20 alerts). Alerts are replayed automatically with mutex protection (`_isProcessingSosQueue`) upon network connectivity restoration or app resume.
- **Session Keys**: Active alert and tracking state are preserved across app lifecycles via `safesphere_active_sos_id` and `safesphere_active_sos_resolve_token`.
- **Verified Emergency Helplines**: Native dialer routes are wired directly for `112` (National Emergency), `181` (Women's Helpline), `108` (Disaster/Medical), `101` (Fire), and `1930` (Cyber Fraud).

---

## 4. Backend Layered Architecture (`backend/`)

```
HTTP / WebSocket Request
        │
        ▼
[Security & Rate Limiting Middleware] ─── (CORS, Helmet, RateLimiter, Request Validation)
        │
        ▼
[Express Router: /api/v1/*, /, /track] ── (authRoutes, reportRoutes, markerRoutes, alertRoutes, locationRoutes)
        │
        ▼
[Controllers] ────────────────────────── (authController, reportController, alertController, locationController)
        │
        ▼
[Domain Services] ────────────────────── (authService, tokenService, otpService, geoService, sosService, trackingService)
        │
        ▼
[Data Layer & Models] ────────────────── (userModel, sessionModel, reportModel, markerModel, alertModel, store.js SQLite/Memory)
```

### 4.1 Request & Response Lifecycle
- **Standardized Response Envelope**:
  ```json
  {
    "success": true,
    "message": "Human-readable status summary",
    "data": { ... }
  }
  ```
- **Standardized Error Envelope**:
  ```json
  {
    "success": false,
    "error": {
      "code": "ERROR_CODE",
      "message": "Human-readable description",
      "details": []
    }
  }
  ```

### 4.2 Security Primitives
- **Password Security**: Pure-JS `bcryptjs` hashing with 12 salt rounds.
- **Dual-Token Lifecycle**: 15-minute access tokens (`HS256`) and 7-day refresh tokens tracked in `sessions` table.
- **Cryptographic OTP Engine**: 6-digit random code generation (`crypto.randomInt(100000, 999999)`), 60-second cooldown rate limit, and strict 3-attempt lockout.
- **SOS Capability Credentials**: One-time plaintext `resolveToken` returned to victim on trigger; server persists only SHA-256 `resolveTokenHash`. `toSafeAlert` sanitization guarantees `resolveTokenHash` is never exposed in any GET response (`/sos/active`, `/sos/:id`, `/sos/mine`).
- **Browser Live Tracker Security**: `GET /track` and `GET /?session=...&token=...` serve an inline, zero-dependency HTML tracker page with mandatory headers:
  - `Cache-Control: no-store`
  - `X-Content-Type-Options: nosniff`
  Negative paths fail closed (missing tokens render HTML awaiting shell without server crashes; invalid API tracking tokens return 401 without stack traces).

---

## 5. Real-Time Telemetry & WebSocket Pipeline

- **Stream Path**: `ws://<host>:<port>/ws/sos`
- **Architecture**: In-memory WebSocket client sets manage real-time connections (built-in `ws` server; zero external Redis dependency).
- **Heartbeat & Liveness**: 30-second interval ping/pong pruning stale client sockets.
- **Telemetry Ingestion**: Clients stream 3-second GPS frames containing:
  - `latitude`, `longitude`, `accuracy`, `speed`, `heading`, `batteryLevel`.
- **Fan-Out Architecture**:
  - Ingested SOS distress frames are broadcast to all connected guardian consoles and responders in sub-100ms latency (`SOS_ALERT_BROADCAST`).
  - Tracking rooms (`SUBSCRIBE_TRACKING`, `TRACKING_SNAPSHOT`, `LOCATION_STREAM_UPDATE`, `STREAM_TERMINATE`) multiplex live trip breadcrumbs strictly to authorized session subscribers verified via tracking capability tokens.

---

## 6. Spatial Engine & Proximity Calculations

- **Haversine Great-Circle Distance**:
  Calculates spherical distance between user coordinates $(\phi_1, \lambda_1)$ and target coordinates $(\phi_2, \lambda_2)$:
  $$d = 2R \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)}\right)$$
- **Proximity Filtering**:
  - `/api/v1/markers/nearby`: Performs sub-15ms spatial indexing, filtering safe zones within radius $R$ and returning results sorted in strictly ascending distance order.
  - `/api/v1/reports`: Performs hyperlocal proximity filtering with `latitude`, `longitude`, and `radiusKm` (clamped between 1.0 and 50.0 km, default 10.0 km). When GPS permission is denied or coordinates are null, proximity filtering is cleanly bypassed to return an honest unfiltered global feed.

---

## 7. Zero-Dependency Monorepo Automation

The root `package.json` delegates all commands to zero-dependency Node.js scripts in `scripts/`:

| Command | Script | Description |
| :--- | :--- | :--- |
| `npm run dev` | `scripts/dev.js` | Concurrently boots both the backend API server and frontend preview service. |
| `npm run backend` | `backend/src/server.js` | Boots the Node.js Express REST and WebSocket server. |
| `npm test` | `scripts/test.js` | Executes frontend structural verification, backend test suite, and regression tests. |
| `npm run clean` | `scripts/clean.js` | Recursively removes build caches, node_modules, and temporary artifacts across all directories. |

---
*SafeSphere System Architecture — Documented by the SafeSphere Engineering Team.*
