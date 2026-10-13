# SafeSphere API Specification (REST & WebSocket)

**Base URL**: `http://127.0.0.1:8000/api/v1`  
**WebSocket URL**: `ws://127.0.0.1:8000/ws/sos`  
**Authentication Header**: `Authorization: Bearer <JWT_ACCESS_TOKEN>`

---

## 1. Authentication Endpoints

### 1.1 `POST /auth/signup`
Creates a new citizen profile and returns access token.
- **Request Body**:
  ```json
  {
    "email": "citizen@safesphere.org",
    "name": "Citizen Jane",
    "phone": "+91 9876543210",
    "password": "StrongPassword!2026",
    "pin": "1234",
    "emergency_contacts": [
      {
        "name": "Mom",
        "phone": "+91 9876500001",
        "relationship": "Mother"
      }
    ]
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "access_token": "eyJhbGciOi...",
    "token_type": "bearer",
    "user": {
      "id": "user_1728800000000",
      "email": "citizen@safesphere.org",
      "name": "Citizen Jane",
      "phone": "+91 9876543210",
      "emergency_contacts": [...],
      "is_active": true,
      "biometrics_enabled": false,
      "has_pin": true,
      "created_at": "2026-10-13T11:00:00"
    }
  }
  ```

### 1.2 `POST /auth/login`
Authenticates via email/phone and password.
- **Request Body**:
  ```json
  {
    "email_or_phone": "citizen@safesphere.org",
    "password": "StrongPassword!2026"
  }
  ```
- **Response `200 OK`**: `TokenResponse`

### 1.3 `POST /auth/login-pin`
Authenticates via 4-digit Safety PIN.
- **Request Body**:
  ```json
  {
    "email": "citizen@safesphere.org",
    "pin": "1234"
  }
  ```
- **Response `200 OK`**: `TokenResponse`

### 1.4 `GET /auth/me`
Retrieves authenticated user profile.
- **Headers**: `Authorization: Bearer <TOKEN>`
- **Response `200 OK`**: `UserResponse`

---

## 2. Emergency SOS Endpoints

### 2.1 `POST /sos/trigger`
Dispatches critical emergency alert.
- **Headers**: `Authorization: Bearer <TOKEN>`
- **Request Body**:
  ```json
  {
    "latitude": 28.6139,
    "longitude": 77.2090,
    "accuracy": 4.5,
    "battery_level": 82,
    "alert_type": "CRITICAL_SOS",
    "notes": "Cornered near metro exit"
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "id": "sos_1728801234000",
    "user_id": "user_001",
    "user_name": "Citizen Jane",
    "user_phone": "+91 9876543210",
    "latitude": 28.6139,
    "longitude": 77.2090,
    "alert_type": "CRITICAL_SOS",
    "status": "active",
    "triggered_at": "2026-10-13T11:15:00",
    "emergency_contacts_notified": 2
  }
  ```

### 2.2 `GET /sos/active`
Retrieves list of active emergencies.

### 2.3 `POST /sos/{id}/resolve`
Cancels/resolves emergency with optional security PIN confirmation.
- **Request Body**:
  ```json
  {
    "reason": "Safe with family",
    "pin": "1234"
  }
  ```

---

## 3. Incident Reports Endpoints

### 3.1 `GET /reports`
- **Query Params**: `status` (`pending`, `under_investigation`, `verified`, `resolved`), `type` (`Theft`, `Harassment`, `Accident`, `Suspicious`), `limit` (int)

### 3.2 `POST /reports`
- **Request Body**:
  ```json
  {
    "type": "Harassment",
    "description": "Poor lighting in lane behind market",
    "location": "Sector 14 Main Alley",
    "latitude": 28.6150,
    "longitude": 77.2105
  }
  ```

---

## 4. Safety Markers Endpoints

### 4.1 `GET /markers/nearby`
- **Query Params**: `latitude`, `longitude`, `radius_km` (default: 10.0)
- **Response `200 OK`**: Array of `MarkerResponse` sorted by Haversine distance.

---

## 5. Real-Time WebSocket (`/ws/sos`)

- **Protocol**: `ws://` / `wss://`
- **Payload Ingestion**:
  ```json
  {
    "user_id": "user_001",
    "latitude": 28.6139,
    "longitude": 77.2090,
    "timestamp": 1728801234
  }
  ```
- **Broadcast Outflow**:
  ```json
  {
    "event": "LOCATION_TELEMETRY",
    "data": { ... }
  }
  ```
