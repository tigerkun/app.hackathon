# SafeSphere Backend Service

Production-grade emergency safety and dispatch backend service powered by Node.js, Express, WebSockets, and SQLite (via Node.js built-in `node:sqlite`), featuring dual-token JWT authentication, real-time SOS broadcasting, and live GPS streaming.

## Architecture

- **Auth & Session**: `/api/v1/auth` (Register, Login, Quick-PIN access, SMS OTP flow, Refresh, Me, Logout)
- **Incident Reports**: `/api/v1/reports` (Submission, Category filtering, Verified community alerts)
- **Emergency SOS**: `/api/v1/sos` (1-touch critical SOS broadcast, emergency contact dispatch, PIN cancellation)
- **Safety Markers**: `/api/v1/markers` (Verified safe zones, police stations, hospitals, Haversine geospatial proximity queries)
- **Real-time Geolocation**: `/api/v1/location` (Live tracking pings, temporary share-sessions)
- **WebSockets**: `/ws/sos` (Bi-directional real-time alert and live GPS stream)
- **Health Check**: `/health` (Operational health with uptime and database status) and `/healthz` (liveness probe)

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
npm test
```
