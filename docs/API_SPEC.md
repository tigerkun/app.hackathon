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
Activates emergency distress session and initiates contact dispatch.
- **Headers**: `Authorization: Bearer <JWT_ACCESS_TOKEN>` (or anonymous guest distress)
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
      "emergencyContactsNotified": 2
    }
  }
  ```

### 2.2 `GET /api/v1/sos/active`
Retrieves list of active emergency incidents.
- **Response `200 OK`**: Array of active `SOSAlert` objects.

### 2.3 `POST /api/v1/sos/{id}/resolve`
Resolves and archives active emergency session.
- **Request Body**:
  ```json
  {
    "reason": "Safe with family",
    "pin": "1234"
  }
  ```
- **Response `200 OK`**: `{ success: true, message: "SOS alert resolved successfully" }`

---

## 3. Incident Reports Endpoints (`/api/v1/reports`)

### 3.1 `GET /api/v1/reports`
Lists community hazard and incident reports.
- **Query Parameters**:
  - `type`: `Theft`, `Harassment`, `Accident`, `Suspicious`, `Other`
  - `status`: `pending`, `under_investigation`, `verified`, `resolved`
  - `limit`: integer (default: 50)
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

## 4. Safety Markers Endpoints (`/api/v1/markers`)

### 4.1 `GET /api/v1/markers`
Lists all safety infrastructure markers.

### 4.2 `GET /api/v1/markers/nearby`
Finds verified safe zones, police stations, and hospitals near coordinates using Haversine spherical distance.
- **Query Parameters**:
  - `latitude` (or `lat`): double (required)
  - `longitude` (or `lon` / `lng`): double (required)
  - `radiusKm`: double (default: 10.0)
  - `category`: string (optional)
- **Response `200 OK`**: Array of markers sorted in strictly ascending distance order (`distanceKm`).

---

## 5. Real-Time Telemetry WebSocket Channel (`/ws/sos`)

- **Protocol**: `ws://` / `wss://`
- **Path**: `/ws/sos`
- **Client Frame Ingestion**:
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
- **Server Broadcast Outflow**:
  ```json
  {
    "type": "SOS_ALERT_BROADCAST",
    "data": { ... },
    "relayedAt": "2026-10-13T12:15:03.000Z"
  }
  ```
