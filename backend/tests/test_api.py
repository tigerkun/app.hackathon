import unittest
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.db.repository import db

class TestSafeSphereBackendApi(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_01_health_check(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "healthy")

    def test_02_auth_login_demo_user(self):
        response = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("access_token", data)
        self.assertEqual(data["user"]["email"], "demo@safesphere.org")

    def test_03_auth_login_pin(self):
        response = self.client.post("/api/v1/auth/login-pin", json={
            "email": "demo@safesphere.org",
            "pin": "1234"
        })
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("access_token", data)

    def test_04_auth_signup_new_user(self):
        response = self.client.post("/api/v1/auth/signup", json={
            "email": "testuser@safesphere.org",
            "name": "Alex Safety",
            "phone": "+91 9123456789",
            "password": "SecurePassword123!",
            "pin": "5678",
            "emergency_contacts": [
                {"name": "Brother", "phone": "+91 9999888877", "relationship": "Brother"}
            ]
        })
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("access_token", data)
        self.assertEqual(data["user"]["name"], "Alex Safety")

    def test_05_incident_reports_list_and_create(self):
        # List initial
        resp_list = self.client.get("/api/v1/reports")
        self.assertEqual(resp_list.status_code, 200)
        initial_count = len(resp_list.json())

        # Create new report
        resp_create = self.client.post("/api/v1/reports", json={
            "type": "Theft",
            "description": "Suspicious bag left unattended at bus terminal.",
            "location": "Central Bus Stand, Platform 4",
            "latitude": 28.6200,
            "longitude": 77.2100
        })
        self.assertEqual(resp_create.status_code, 201)
        created_data = resp_create.json()
        self.assertEqual(created_data["type"], "Theft")
        self.assertEqual(created_data["status"], "pending")

        # Verify count increment
        resp_list_after = self.client.get("/api/v1/reports")
        self.assertEqual(len(resp_list_after.json()), initial_count + 1)

    def test_06_sos_trigger_and_resolve(self):
        # Login first
        login_res = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Trigger SOS
        trigger_res = self.client.post("/api/v1/sos/trigger", json={
            "latitude": 28.6139,
            "longitude": 77.2090,
            "alert_type": "CRITICAL_SOS"
        }, headers=headers)
        self.assertEqual(trigger_res.status_code, 201)
        sos_data = trigger_res.json()
        self.assertEqual(sos_data["status"], "active")
        sos_id = sos_data["id"]

        # Check active SOS
        active_res = self.client.get("/api/v1/sos/active")
        self.assertEqual(active_res.status_code, 200)
        active_ids = [s["id"] for s in active_res.json()]
        self.assertIn(sos_id, active_ids)

        # Resolve SOS
        resolve_res = self.client.post(f"/api/v1/sos/{sos_id}/resolve", json={
            "reason": "Test drill finished safely",
            "pin": "1234"
        }, headers=headers)
        self.assertEqual(resolve_res.status_code, 200)
        self.assertEqual(resolve_res.json()["status"], "resolved")

    def test_07_markers_list_and_nearby(self):
        resp = self.client.get("/api/v1/markers")
        self.assertEqual(resp.status_code, 200)
        self.assertGreaterEqual(len(resp.json()), 3)

        nearby_resp = self.client.get("/api/v1/markers/nearby?latitude=28.6139&longitude=77.2090&radius_km=15")
        self.assertEqual(nearby_resp.status_code, 200)
        nearby_data = nearby_resp.json()
        self.assertGreaterEqual(len(nearby_data), 1)

    def test_08_location_ping_and_share_session(self):
        login_res = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Ping location
        ping_res = self.client.post("/api/v1/location/ping", json={
            "latitude": 28.6139,
            "longitude": 77.2090,
            "accuracy": 5.0
        }, headers=headers)
        self.assertEqual(ping_res.status_code, 200)

        # Create share session
        share_res = self.client.post("/api/v1/location/share-session", json={
            "duration_minutes": 30,
            "initial_latitude": 28.6139,
            "initial_longitude": 77.2090
        }, headers=headers)
        self.assertEqual(share_res.status_code, 201)
        session_id = share_res.json()["session_id"]

        # Track session
        track_res = self.client.get(f"/api/v1/location/track/{session_id}")
        self.assertEqual(track_res.status_code, 200)
        self.assertTrue(track_res.json()["is_active"])

if __name__ == "__main__":
    unittest.main()
