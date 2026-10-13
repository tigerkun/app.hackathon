# SafeSphere Enterprise Monorepo

> **SafeSphere** is an enterprise-ready personal safety, emergency response, and community intelligence platform featuring dynamic GPS tracking, emergency telephony integration (112, 181, 108, 101), real-time crowdsourced safety markers, AI safety assistance, and multi-modal authentication.

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
- **Flutter SDK**: `3.x` (optional, required only for native mobile builds)

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

## 4. Documentation Hub

Detailed technical specifications and design documents are located in `docs/`:
- **[Master PRD](docs/PRD.md)**: Product vision, user personas, functional specifications, non-functional security SLAs, and release roadmap.
- **[System Architecture](docs/ARCHITECTURE.md)**: Microservices and mobile architecture, data flow diagrams, and state management.
- **[API Specifications](docs/API_SPEC.md)**: OpenAPI 3.0 REST endpoints, dual-token JWT auth lifecycle, and WebSocket location streaming protocol.

---

## 5. License

Copyright © 2026 SafeSphere Platform Team. Released under the MIT License.
