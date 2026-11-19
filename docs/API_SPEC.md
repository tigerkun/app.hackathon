# SafeSphere API Specification (REST & WebSocket)

**Document Version**: 3.0.0-ENTERPRISE  
**Base REST URL**: `http://127.0.0.1:3000/api/v1`  
**WebSocket URL**: `ws://127.0.0.1:3000/ws/sos`  
**Authentication Header**: `Authorization: Bearer <JWT_ACCESS_TOKEN>`  
**Status**: APPROVED & ACTIVE  

---

## 1. Authentication Endpoints (`/api/v1/auth`)

### 1.1 `POST /api/v1/auth/register` (Alias: `POST /api/v1/auth/signup`)
Creates a new citizen profile with primary emergency contact.
- **Rate Limit**: Enforced via `authLimiter` (10 requests / 15 minutes).
- **Request Body**:
  ```json
  {
    "name": "Priya Sharma",
    "email": "priya@safesphere.org",
    "phone": "+919876543210",
    "password": "SecurePassword123",
    "emergencyContactPhone": "+919876543211",
    "emergencyContactName": "Rajesh Patel",
    "pin": "1234"
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "success": true,
    "message": "User registered successfully",
    "data": {
      "accessToken": "eyJhbGciOiJIUzI1NiIsIn...",
      "refreshToken": "7f8b9a1c2d3e4f5a6b7c8d9e0f1a2b3c...",
      "user": {
        "id": "usr_1728800000_a1b2",
        "name": "Priya Sharma",
        "email": "priya@safesphere.org",
        "phone": "+919876543210",
        "hasPin": true,
        "biometricsEnabled": false,
        "emergencyContacts": [
          {
            "name": "Rajesh Patel",
            "phone": "+919876543211",
            "relationship": "Emergency Contact",
            "isPrimary": true
          }
        ],
        "isActive": true,
        "createdAt": "2026-10-13T12:00:00.000Z"
      }
    }
  }
  ```

### 1.2 `POST /api/v1/auth/login`
Authenticates via email or phone and password.
- **Request Body**:
  ```json
  {
    "emailOrPhone": "priya@safesphere.org",
    "password": "SecurePassword123"
  }
  ```
- **Response `200 OK`**: Standard auth envelope with `accessToken`, `refreshToken`, and sanitized `user`.

### 1.3 `POST /api/v1/auth/login-pin`
Fast authentication via 4-digit stealth PIN.
- **Request Body**:
  ```json
  {
    "emailOrPhone": "+919876543210",
    "pin": "1234"
  }
  ```
- **Response `200 OK`**: Standard auth envelope.

### 1.4 `POST /api/v1/auth/otp/send`
Dispatches 6-digit cryptographic SMS OTP.
- **Rate Limit**: 60-second cooldown per phone number.
- **Request Body**:
  ```json
  {
    "phone": "+919876543210"
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "message": "OTP sent successfully",
    "data": {
      "expiresInSeconds": 300,
      "cooldownSeconds": 60
    }
  }
  ```

### 1.5 `POST /api/v1/auth/otp/verify`
Verifies OTP code and establishes session.
- **Lockout**: 3 failed attempts invalidates OTP record.
- **Request Body**:
  ```json
  {
    "phone": "+919876543210",
    "otp": "849201"
  }
  ```
- **Response `200 OK`**: Standard auth envelope.

### 1.6 `POST /api/v1/auth/refresh`
Exchanges valid refresh token for fresh access token.
- **Request Body**:
  ```json
  {
    "refreshToken": "7f8b9a1c2d3e4f5a6b7c8d9e0f1a2b3c..."
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "data": {
      "accessToken": "eyJhbGciOiJIUzI1NiIsIn...",
      "refreshToken": "7f8b9a1c2d3e4f5a6b7c8d9e0f1a2b3c..."
    }
  }
  ```

### 1.7 `GET /api/v1/auth/me`
Retrieves authenticated citizen profile and emergency contacts.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>`
- **Response `200 OK`**: `{ success: true, data: { user } }`

### 1.8 `POST /api/v1/auth/logout`
Revokes active session and invalidates refresh token.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>`
- **Response `200 OK`**: `{ success: true, message: "Logged out successfully" }`

---

## 2. Emergency SOS Endpoints (`/api/v1/sos`)

### 2.1 `POST /api/v1/sos/start` (Alias: `POST /api/v1/sos/trigger`)
Activates emergency distress session, notifies emergency contacts, and issues a one-time self-resolution credential.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>` (optional; supports anonymous guest distress)
- **Request Body**:
  ```json
  {
    "latitude": 28.6139,
    "longitude": 77.2090,
    "accuracy": 4.5,
    "batteryLevel": 82,
    "alertType": "CRITICAL_SOS",
    "notes": "Cab driver deviated route"
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "success": true,
    "message": "SOS alert triggered successfully",
    "data": {
      "id": "sos_1728801234_abc",
      "userId": "usr_001",
      "userName": "Priya Sharma",
      "userPhone": "+919876543210",
      "latitude": 28.6139,
      "longitude": 77.2090,
      "alertType": "CRITICAL_SOS",
      "status": "active",
      "triggeredAt": "2026-10-13T12:15:00.000Z",
      "emergencyContactsNotified": 2,
      "resolveToken": "SmQD0GBEW6k8..."
    }
  }
  ```
  > **Security Invariant**: `resolveToken` is returned in plaintext **strictly once** upon alert creation. The backend stores only its SHA-256 cryptographic digest (`resolveTokenHash`). Under no circumstances is `resolveTokenHash` returned in any public or authenticated GET endpoint.

### 2.2 `GET /api/v1/sos/active`
Retrieves list of active emergency incidents for emergency responders and community monitors.
- **Response `200 OK`**: Array of active `SOSAlert` objects with live telemetry and `monitorsConnected` (count of WebSocket clients listening on `/ws/sos`). `resolveTokenHash` is strictly scrubbed.

### 2.3 `GET /api/v1/sos/mine`
Retrieves incident history for the authenticated citizen.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>` (required; 401 if missing)
- **Query Parameters**:
  - `status`: string (optional: `active`, `resolved`)
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "count": 1,
    "data": [
      {
        "id": "sos_1728801234_abc",
        "userId": "usr_001",
        "latitude": 28.6139,
        "longitude": 77.2090,
        "alertType": "CRITICAL_SOS",
        "status": "active",
        "monitorsConnected": 3,
        "triggeredAt": "2026-10-13T12:15:00.000Z",
        "resolvedAt": null
      }
    ]
  }
  ```

### 2.4 `POST /api/v1/sos/{id}/resolve`
Resolves and archives an active emergency session.
- **Authorization**:
  - Authenticated user: Verified against user PIN (`pin`).
  - Anonymous distress / Victim self-resolution: Verified against `resolveToken` (passed in JSON body via `resolveToken`, `resolve_token`, or `token`).
  - Responders / Admins: Authorized via role credential.
  - Legacy alerts without stored hash fail closed (401/403) for token bearers while remaining resolvable by responders/admins.
- **Request Body (PIN Resolution)**:
  ```json
  {
    "reason": "Safe with family",
    "pin": "1234"
  }
  ```
- **Request Body (Capability Token Resolution)**:
  ```json
  {
    "reason": "False alarm cancelled",
    "resolveToken": "SmQD0GBEW6k8..."
  }
  ```
- **Response `200 OK`**: `{ success: true, message: "SOS alert resolved successfully" }`

---

## 3. Incident Reports Endpoints (`/api/v1/reports`)

### 3.1 `GET /api/v1/reports`
Lists community hazard and incident reports with optional proximity filtering.
- **Query Parameters**:
  - `latitude` (or `lat`): double (optional — user latitude)
  - `longitude` (or `lon` / `lng`): double (optional — user longitude)
  - `radiusKm`: double (optional — search radius; clamped strictly between 1.0 and 50.0 km, default: 10.0 km)
  - `type`: string (optional: `Theft`, `Harassment`, `Accident`, `Suspicious`, `Other`)
  - `status`: string (optional: `pending`, `under_investigation`, `verified`, `resolved`)
  - `limit`: integer (default: 50)
- **Proximity & Honesty Behavior**:
  - When both `latitude` and `longitude` are provided, the backend computes Haversine spherical distance and filters reports within `radiusKm`, returning results with `distanceKm` metadata.
  - When GPS permission is denied or coordinates are omitted, the API serves an honest global feed without distance filtering.
- **Response `200 OK`**: `{ success: true, count: N, data: [ ... ] }`

### 3.2 `POST /api/v1/reports`
Submits a new community hazard report.
- **Request Body**:
  ```json
  {
    "type": "Harassment",
    "description": "Poor lighting in lane behind market",
    "location": "Sector 14 Main Road",
    "latitude": 28.6150,
    "longitude": 77.2105
  }
  ```
- **Response `201 Created`**: Standard report envelope.

### 3.3 `GET /api/v1/reports/{id}`
Retrieves a specific report by unique identifier.

---

## 4. Location Tracking & Browser Tracker (`/api/v1/location`, `/track`, `GET /`)

### 4.1 `POST /api/v1/location/share-session`
Initiates a temporary live tracking session and generates a shareable capability link.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>` (optional; guests allowed)
- **Request Body**:
  ```json
  {
    "latitude": 28.6139,
    "longitude": 77.2090,
    "accuracy": 5.0,
    "durationMinutes": 60
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "success": true,
    "data": {
      "sessionId": "trk_1728800000_01a",
      "token": "78118121ebdd358b84ad1907310ecfa8",
      "shareUrl": "https://api.safesphere.org/?session=trk_1728800000_01a&token=78118121ebdd358b84ad1907310ecfa8",
      "expiresAt": "2026-10-13T13:15:00.000Z"
    }
  }
  ```

### 4.2 `GET /api/v1/location/track/{sessionId}`
Retrieves live session state and breadcrumb history for authorized guardians.
- **Authentication**: Tracking token is mandatory via query parameter `?token=<token>`, header `Authorization: Bearer <token>`, or body `token`.
- **Response `200 OK`**:
  ```json
  {
    "success": true,
    "data": {
      "sessionId": "trk_1728800000_01a",
      "status": "active",
      "breadcrumbs": [
        {
          "latitude": 28.6139,
          "longitude": 77.2090,
          "accuracy": 5.0,
          "speed": 1.2,
          "heading": 180.0,
          "batteryLevel": 85,
          "recordedAt": "2026-10-13T12:15:00.000Z"
        }
      ],
      "expiresAt": "2026-10-13T13:15:00.000Z"
    }
  }
  ```
- **Error Responses**:
  - `401 Unauthorized` with `MISSING_TRACKING_TOKEN` when token is absent.
  - `401 Unauthorized` with `INVALID_TRACKING_TOKEN` when token does not match session.
  - Zero stack traces leaked in error envelope.

### 4.3 `POST /api/v1/location/ping`
Appends a live breadcrumb to an active tracking session.
- **Request Body**:
  ```json
  {
    "sessionId": "trk_1728800000_01a",
    "token": "78118121ebdd358b84ad1907310ecfa8",
    "latitude": 28.6145,
    "longitude": 77.2095,
    "accuracy": 4.2,
    "speed": 1.5,
    "heading": 182.0,
    "batteryLevel": 84
  }
  ```
- **Response `200 OK`**: `{ success: true, message: "Location ping recorded" }`

### 4.4 `POST /api/v1/location/terminate/{sessionId}`
Explicitly ends an active live tracking session.
- **Request Body / Query**: `token=<token>`
- **Response `200 OK`**: `{ success: true, message: "Tracking session terminated" }`

### 4.5 Browser Inline Tracker Viewer (`GET /track` and `GET /?session={id}&token={token}`)
Zero-dependency, standalone HTML viewer served directly by the backend for desktop/mobile browsers.
- **Routes**:
  - `GET /?session=<id>&token=<token>` (also accepts `sessionId`)
  - `GET /track?session=<id>&token=<token>` (or bare `GET /track`)
- **Mandatory Security Headers**:
  - `Content-Type: text/html; charset=utf-8`
  - `Cache-Control: no-store` (guarantees dynamic live coordinates are never cached by proxies, browsers, or CDNs)
  - `X-Content-Type-Options: nosniff` (prevents MIME-sniffing exploits)
- **Negative Paths & Resilience**:
  - Missing token parameters render an HTML awaiting/error state shell without crashing or leaking server stack traces.
  - Bare `GET /` without tracking query parameters continues to serve standard API service JSON metadata.

---

## 5. Safety Markers Endpoints (`/api/v1/markers`)

### 5.1 `GET /api/v1/markers`
Lists all safety infrastructure markers.

### 5.2 `GET /api/v1/markers/nearby`
Finds verified safe zones, police stations, and hospitals near coordinates using Haversine spherical distance.
- **Query Parameters**:
  - `latitude` (or `lat`): double (required)
  - `longitude` (or `lon` / `lng`): double (required)
  - `radiusKm`: double (default: 10.0)
  - `category`: string (optional)
- **Response `200 OK`**: Array of markers sorted in strictly ascending distance order (`distanceKm`).

---

## 6. Real-Time Telemetry & WebSocket Pipeline (`/ws/sos`)

- **Protocol**: `ws://` / `wss://`
- **Path**: `/ws/sos`
- **Architecture**: In-memory WebSocket client sets (zero Redis dependency).
- **Client Ingestion Frames**:
  - `SOS_TELEMETRY`:
    ```json
    {
      "type": "SOS_TELEMETRY",
      "sosId": "sos_1728801234_abc",
      "latitude": 28.613929,
      "longitude": 77.209021,
      "accuracy": 4.5,
      "speed": 1.2,
      "heading": 184.2,
      "batteryLevel": 78
    }
    ```
  - `SUBSCRIBE_TRACKING`:
    ```json
    {
      "type": "SUBSCRIBE_TRACKING",
      "sessionId": "trk_1728800000_01a",
      "token": "78118121ebdd358b84ad1907310ecfa8"
    }
    ```
- **Server Broadcast Outflow**:
  - `SOS_ALERT_BROADCAST`: Broadcast to all connected clients upon SOS trigger.
  - `TRACKING_SNAPSHOT`: Initial breadcrumbs snapshot sent to joining guardians.
  - `LOCATION_STREAM_UPDATE`: Live breadcrumbs pushed to guardians subscribed to `sessionId`.
  - `STREAM_TERMINATE`: Notification sent to room subscribers when tracking session ends.
