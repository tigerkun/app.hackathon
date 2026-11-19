# SafeSphere Backend Service

Production-grade emergency safety and dispatch backend service powered by Node.js, Express, WebSockets, and SQLite (via Node.js built-in `node:sqlite`), featuring dual-token JWT authentication, real-time SOS broadcasting, and live GPS streaming.

## Architecture

- **Auth & Session**: `/api/v1/auth` (Register, Login, Quick-PIN access, SMS OTP flow, Refresh, Me, Logout)
- **Incident Reports**: `/api/v1/reports` (Submission, Category filtering, Verified community alerts, Hyperlocal proximity filtering via `latitude`, `longitude`, and `radiusKm` clamped between 1–50 km, default 10 km; honest global fallback when coordinates are omitted)
- **Emergency SOS**: `/api/v1/sos` (1-touch critical SOS broadcast, emergency contact dispatch, self-resolution via one-time `resolveToken`, citizen alert history via `GET /api/v1/sos/mine` with `?status=active|resolved` filtering, and live `monitorsConnected` counts in alert payloads; `resolveTokenHash` strictly sanitized)
- **Safety Markers**: `/api/v1/markers` (Verified safe zones, police stations, hospitals, Haversine geospatial proximity queries)
- **Real-Time Geolocation & Browser Tracking**:
  - `/api/v1/location`: Live tracking pings (`/ping`), temporary share-sessions (`/share-session`), session status (`/track/:sessionId`), and termination (`/terminate/:sessionId`)
  - `/track` & `GET /?session=<id>&token=<token>`: Zero-dependency inline HTML tracker page with mandatory security headers (`Cache-Control: no-store`, `X-Content-Type-Options: nosniff`); negative paths fail closed with 401 on missing/invalid tracking tokens without leaking stack traces
- **WebSockets**: `/ws/sos` (Bi-directional real-time alert and live GPS stream using built-in in-memory WebSocket client sets, supporting `SUBSCRIBE_TRACKING`, `TRACKING_SNAPSHOT`, `LOCATION_STREAM_UPDATE`, and `STREAM_TERMINATE`)
- **Health Checks**: `/health` (Operational health with uptime, database status, and active client count) and `/healthz` (liveness probe)

## Getting Started

### Prerequisites
- Node.js 18.0.0+ (v24.x recommended)
- npm 9.x+

### Run Development Server
```bash
npm start
# or hot-reload dev mode:
npm run dev
```

### Run Tests
```bash
# Automated unit and integration test suite (169 tests across 42 suites)
npm test

# Live end-to-end smoke test suite (11/11 passed across 4 phases)
npm run smoke
```
