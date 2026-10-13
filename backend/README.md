# SafeSphere Backend Service

Production-grade emergency safety and dispatch backend service powered by FastAPI, Pydantic, WebSockets, and secure JWT / PBKDF2 authentication.

## Architecture

- **Auth & Session**: `/api/v1/auth` (Signup, Login, Refresh, Me, Quick-PIN access, Biometric credential exchange)
- **Incident Reports**: `/api/v1/reports` (Submission, Category filtering, Verified community alerts)
- **Emergency SOS**: `/api/v1/sos` (1-touch critical SOS broadcast, emergency contact dispatch, PIN cancellation)
- **Safety Markers**: `/api/v1/markers` (Verified safe zones, police stations, hospitals, Haversine geospatial proximity queries)
- **Real-time Geolocation**: `/api/v1/location` (Live tracking pings, temporary share-sessions)
- **WebSockets**: `/ws/sos` (Bi-directional real-time alert and live GPS stream)

## Getting Started

### Prerequisites
- Python 3.10+
- `fastapi`, `uvicorn`, `pydantic`

### Run Development Server
```bash
uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload
```

### Run Tests
```bash
python -m unittest backend/tests/test_api.py
```

### Interactive API Documentation
- Swagger UI: `http://127.0.0.1:8000/docs`
- ReDoc: `http://127.0.0.1:8000/redoc`
