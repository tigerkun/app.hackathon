# SafeSphere — Product Requirements Document (PRD)

**Document Version**: 2.0.0  
**Status**: APPROVED & ACTIVE  
**Last Updated**: October 2026  
**Target Platform**: Mobile (Flutter / Android / iOS), Web Preview (HTML5/ES6), Backend Services (Python FastAPI / Node.js)

---

## 1. Executive Summary & Vision

### 1.1 Mission Statement
SafeSphere empowers citizens with a zero-friction, mission-critical personal safety companion and community intelligence platform. When a citizen is in danger, every microsecond counts; SafeSphere delivers instant 1-touch emergency helpline dialing (`112`, `181`, `108`, `101`), high-precision live GPS tracking with fallback redundancy, crowd-sourced verifiable incident reporting, and contextual AI safety guidance.

### 1.2 Core Problem Statement
Existing personal safety applications fail in real-world crises due to:
1. **Fragile Network Assumptions**: Crashing or freezing when GPS permissions are denied or when cell tower reception drops in basements/tunnels.
2. **Delayed Emergency Callouts**: Forcing users through multi-layer menus or login walls when under active threat.
3. **Monolithic Spaghetti Code**: Tightly coupled mobile interfaces lacking modular backend architectures, shared contracts, or automated test pipelines.
4. **Privacy Leaks**: Exposing location data continuously rather than on-demand with cryptographic privacy guarantees.

---

## 2. User Personas & Use Cases

| Persona | Demographics / Profile | Primary Need | Critical SafeSphere Feature |
|---|---|---|---|
| **P1: The Lone Commuter (Priya, 24)** | Software Engineer traveling late on night transit. | Wants loved ones to know her exact path without needing active phone interaction. | **Live Location Share**: One-tap share session with live expiring link. |
| **P2: The Panicked Citizen (Aarav, 19)** | College student cornered in a deserted alley. | Needs immediate emergency helpline connection without unlocking screen menus. | **1-Touch SOS Hub & 112 Dialing**: Direct telephony intent launch (`tel:112`) with fallback default coordinates. |
| **P3: The Community Guardian (Sunita, 42)** | Neighborhood watch leader tracking local incidents. | Needs verifiable reports on suspicious activity, broken streetlights, or harassment. | **Incident Crowdsourcing & Verified Safe Zones**: Geo-tagged reports with status lifecycles. |
| **P4: First Responder / Dispatcher (Officer Rajesh)** | Emergency service agent coordinating field units. | Needs low-latency telemetry and spatial proximity queries for safe extraction. | **Nearby Markers API**: Haversine distance-calculated safe havens and live WebSocket alerts. |

---

## 3. High-Level System Architecture

SafeSphere is architecturally organized into decoupled tiers:
```
safesphere/
├── backend/                  # FastAPI / Python microservice with WebSocket dispatch
│   ├── app/
│   │   ├── api/v1/          # Endpoints: auth, reports, sos, markers, location
│   │   ├── core/            # Config, PBKDF2 cryptography, JWT tokens
│   │   ├── db/              # High-fidelity repository with demo seeds
│   │   └── models/          # Pydantic schemas and DTOs
│   └── tests/               # Backend integration and unit test suite
├── frontend/                 # Client presentations
│   ├── mobile/              # Flutter mobile app architecture guide
│   └── web_preview/         # Zero-install interactive web application
├── shared/                   # Cross-tier contracts and schemas
│   ├── contracts/           # OpenAPI 3.1 specification (api_contracts.json)
│   └── types/               # TypeScript & Dart shared type definitions
├── docs/                     # PRD, Architecture, and API specifications
├── automation/               # Automated pipeline and booster scripts
│   ├── boost.ps1 / .sh      # One-click environment booster
│   └── automation.ps1 / .sh # Full CI test and validation pipeline
├── lib/                      # Flutter mobile production application
└── test/                     # Flutter test suites (R1 - R5) and challenger tests
```

---

## 4. Functional Requirements

### FR-1: Authentication & Identity Management
- **FR-1.1**: Email & Phone sign-up with password hashing via PBKDF2-HMAC-SHA256 (100,000 iterations).
- **FR-1.2**: 4-digit Security PIN (`login-pin`) allowing swift authorization during elevated stress.
- **FR-1.3**: Biometric credential token registration (FaceID / Fingerprint) with fallback to PIN.
- **FR-1.4**: Emergency Guest Mode / Crisis Bypass: Critical SOS and Helpline dialing MUST NEVER be blocked behind an authentication paywall.

### FR-2: Emergency Crisis & Telephony Dialing
- **FR-2.1**: Direct telephony launching (`tel:112`, `tel:181`, `tel:108`, `tel:101`) conforming to RFC 3966.
- **FR-2.2**: Zero crash risk on platform telephony launch failures, displaying user-informative feedback without unmounted widget state corruption.
- **FR-2.3**: Re-entrant callout protection preventing platform IPC thread pool exhaustion during panic tapping.

### FR-3: Geospatial Intelligence & Live Tracking
- **FR-3.1**: Dynamic GPS lock via hardware geolocator with timeout-guarded fallback to `getLastKnownPosition()`.
- **FR-3.2**: Safe fallback to verified metropolitan coordinates (`28.6139, 77.2090`) when permissions are denied or service is disabled.
- **FR-3.3**: Interactive map tiles (Google Maps / Leaflet) rendering verified safe zones, police stations, and caution areas.
- **FR-3.4**: Proximity queries using Haversine distance calculations returning nearest help stations within $N$ kilometers.

### FR-4: Incident Reporting & Community Intelligence
- **FR-4.1**: Multi-category incident taxonomy: `Theft`, `Harassment`, `Accident`, `Suspicious`, `Other`.
- **FR-4.2**: Client-side validation: empty or whitespace-only descriptions are rejected with clear user feedback.
- **FR-4.3**: Status transition state machine: `pending` $\rightarrow$ `under_investigation` $\rightarrow$ `verified` $\rightarrow$ `resolved`.

### FR-5: AI Safety Assistant
- **FR-5.1**: Context-aware emergency guidance for de-escalation, navigation in poorly lit zones, and panic alleviation.
- **FR-5.2**: FIFO message processing with unmounted lifecycle guards preventing memory leaks during rapid screen transitions.

---

## 5. Non-Functional Requirements (NFR)

1. **Crash Immunity**: $0\%$ unhandled platform exceptions on denied hardware permissions (GPS, Phone, Camera).
2. **Latency Standards**:
   - Emergency dialer trigger: $< 150\text{ ms}$.
   - Live location ping ingestion: $< 100\text{ ms}$.
   - WebSocket broadcast to responders: $< 250\text{ ms}$.
3. **Accessibility (WCAG 2.1 AA)**: All text elements across light and dark themes MUST meet or exceed a $4.5:1$ contrast ratio over background surfaces.
4. **Security & Privacy**:
   - Passwords salted with 16-byte random values.
   - JWT sessions signed via HS256 with auto-expiration.
   - Live location sharing URLs cryptographically randomized with TTL bounds.

---

## 6. Product Roadmap

### Phase 1: Foundations & Architecture (Completed - Current Release)
- Clean mono-repo directory structure separating `backend/`, `frontend/`, `shared/`, `docs/`, and `automation/`.
- Full FastAPI backend implementation with REST endpoints, WebSockets, and integration tests.
- Flutter mobile Auth models, services, screens (`LoginPage`, `SignupPage`, `AuthPinPage`).
- Shared OpenAPI 3.1 contracts and TypeScript DTOs.
- Automated dev booster (`boost.ps1`) and pipeline runner (`automation.ps1`).

### Phase 2: Mesh & Offline Sync (Q1 2027)
- Bluetooth Low Energy (BLE) peer-to-peer mesh broadcasting for network-dead zones.
- SQLite local database offline sync with background workmanager.

### Phase 3: Hardware Wearables & Duress PIN (Q2 2027)
- WearOS and Apple Watch companion app with accelerometer fall-detection.
- Duress PIN (e.g. entering decoy PIN silently alerts police while presenting normal UI).

### Phase 4: Smart City Dispatch Integration (Q3 2027)
- Direct integration with municipal 112 ERSS (Emergency Response Support System) dispatch APIs.
- Automated CAD (Computer-Aided Dispatch) packet handoff.
