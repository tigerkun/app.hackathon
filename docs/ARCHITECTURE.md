# SafeSphere System Architecture Specification

## 1. High-Level Tier Diagram

```
+---------------------------------------------------------------------------------+
|                                 CLIENT TIER                                     |
|  +-------------------------------------+  +----------------------------------+  |
|  |     Flutter Mobile App (Native)     |  |   Web Preview / Dispatch Client  |  |
|  |  - Glassmorphic UI (WCAG AA Compl.) |  |   - Leaflet / OpenStreetMap      |  |
|  |  - Hardware GPS & Telephony Intents |  |   - Zero-Install Emergency UI    |  |
|  |  - AuthService & Biometric Locks    |  |   - Session & Security PIN Modal |  |
|  +-------------------------------------+  +----------------------------------+  |
+----------------------------------------+----------------------------------------+
                                         | REST & WebSockets (JSON Contracts)
                                         v
+---------------------------------------------------------------------------------+
|                                BACKEND TIER                                     |
|  +---------------------------------------------------------------------------+  |
|  |                         FastAPI Core Application                          |  |
|  |  +----------------+  +-----------------+  +----------------------------+  |  |
|  |  | /api/v1/auth   |  | /api/v1/sos     |  | /api/v1/reports            |  |  |
|  |  | - PBKDF2 Hash  |  | - Emergency     |  | - Multi-category incident  |  |  |
|  |  | - JWT Tokens   |  |   Dispatch      |  |   lifecycle & validation   |  |  |
|  |  | - PIN & Bio    |  | - Contact Broadcast|                             |  |  |
|  |  +----------------+  +-----------------+  +----------------------------+  |  |
|  |  +------------------------------------+   +----------------------------+  |  |
|  |  | /api/v1/markers & /location        |   | /ws/sos Stream Manager     |  |  |
|  |  | - Haversine Proximity (<10km)      |   | - Real-time Responder Push |  |  |
|  |  | - Live Track Session Generator     |   | - GPS Telemetry Broadcast  |  |  |
|  |  +------------------------------------+   +----------------------------+  |  |
|  +---------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------+
                                         |
                                         v
+---------------------------------------------------------------------------------+
|                           SHARED CONTRACTS TIER                                 |
|  - OpenAPI 3.1 Contract: shared/contracts/api_contracts.json                    |
|  - TypeScript Contracts: shared/types/*.ts                                      |
|  - Dart Data Transfer Objects: lib/models/*.dart                                |
+---------------------------------------------------------------------------------+
```

## 2. Directory Layout Rationale

1. **`backend/`**: Encapsulates all server logic, dependency isolation (`requirements.txt`), FastAPI route blueprints, security primitives, and automated test runners.
2. **`frontend/`**: Hosts documentation and web client assets (`web_preview/`).
3. **`lib/`**: Flutter mobile application code base organized according to domain layers (`pages/`, `models/`, `services/`, `theme/`, `widgets/`, `data/`).
4. **`shared/`**: Contains cross-platform schemas and contracts ensuring the Flutter app, Web Preview, and backend stay synchronized.
5. **`docs/`**: Central knowledge base containing PRD, architecture, and API documentation.
6. **`automation/`**: Standard automation tools for continuous testing, dependency checks, and dev environment boosting.

## 3. Security & Cryptography Standards

- **Password Hashing**: PBKDF2 using SHA-256 with 100,000 rounds and unique per-user 16-byte salt strings.
- **Session Tokens**: JWT containing `sub` (User ID), `email`, and `exp` claims signed via HMAC-SHA256.
- **Hardware Dialing**: Unsanitized phone strings are normalized before creating telephony URIs:
  $$\text{URI} = \text{"tel:"} + \text{sanitized\_digits}$$
- **GPS Coordinates**: Handled as 64-bit IEEE 754 floating point numbers bounded strictly to latitude $[-90.0, 90.0]$ and longitude $[-180.0, 180.0]$.
