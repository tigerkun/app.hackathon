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

    def test_09_sos_pin_bypass_adversarial_rejection(self):
        login_res = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Trigger SOS
        trig_res = self.client.post("/api/v1/sos/trigger", json={
            "latitude": 28.5,
            "longitude": 77.2,
            "alert_type": "CRITICAL_SOS"
        }, headers=headers)
        sos_id = trig_res.json()["id"]

        # Attempt to resolve WITHOUT PIN (must be rejected 403 because demo user has PIN 1234)
        resolve_no_pin = self.client.post(f"/api/v1/sos/{sos_id}/resolve", json={
            "reason": "Attempting unverified cancel"
        }, headers=headers)
        self.assertEqual(resolve_no_pin.status_code, 403)

        # Attempt to resolve with WRONG PIN
        resolve_wrong_pin = self.client.post(f"/api/v1/sos/{sos_id}/resolve", json={
            "reason": "Attempting bad PIN",
            "pin": "9999"
        }, headers=headers)
        self.assertEqual(resolve_wrong_pin.status_code, 403)

        # Clean resolve with CORRECT PIN
        resolve_ok = self.client.post(f"/api/v1/sos/{sos_id}/resolve", json={
            "reason": "Safe now",
            "pin": "1234"
        }, headers=headers)
        self.assertEqual(resolve_ok.status_code, 200)

    def test_10_sos_unauthorized_user_rejection(self):
        # User A triggers SOS
        login_a = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        tok_a = login_a.json()["access_token"]
        trig = self.client.post("/api/v1/sos/trigger", json={
            "latitude": 28.5,
            "longitude": 77.2,
            "alert_type": "CRITICAL_SOS"
        }, headers={"Authorization": f"Bearer {tok_a}"})
        sos_id = trig.json()["id"]

        # User B registers & tries to resolve User A's SOS
        signup_b = self.client.post("/api/v1/auth/signup", json={
            "email": "intruder@safesphere.org",
            "name": "Intruder",
            "phone": "+91 9111122223",
            "password": "Password123!",
            "pin": "1234"
        })
        tok_b = signup_b.json()["access_token"]

        # User B attempts to resolve User A's SOS
        unauth_resolve = self.client.post(f"/api/v1/sos/{sos_id}/resolve", json={
            "reason": "I am resolving someone else's SOS",
            "pin": "1234"
        }, headers={"Authorization": f"Bearer {tok_b}"})
        self.assertEqual(unauth_resolve.status_code, 403)

    def test_11_location_ping_updates_share_session(self):
        login_res = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        headers = {"Authorization": f"Bearer {login_res.json()['access_token']}"}

        # Create share session at initial coords
        share_res = self.client.post("/api/v1/location/share-session", json={
            "duration_minutes": 15,
            "initial_latitude": 28.5000,
            "initial_longitude": 77.1000
        }, headers=headers)
        session_id = share_res.json()["session_id"]

        # User moves and pings new GPS coords
        self.client.post("/api/v1/location/ping", json={
            "latitude": 28.5555,
            "longitude": 77.2222
        }, headers=headers)

        # Track session status should now show updated coords
        track = self.client.get(f"/api/v1/location/track/{session_id}")
        self.assertEqual(track.status_code, 200)
        self.assertEqual(track.json()["current_latitude"], 28.5555)
        self.assertEqual(track.json()["current_longitude"], 77.2222)

    def test_12_biometric_register_and_login(self):
        login_res = self.client.post("/api/v1/auth/login", json={
            "email_or_phone": "demo@safesphere.org",
            "password": "SafeSphere@2026"
        })
        headers = {"Authorization": f"Bearer {login_res.json()['access_token']}"}

        # Register new biometric key
        reg_res = self.client.post("/api/v1/auth/biometrics/register", json={
            "biometric_token": "bio_secure_enclave_key_456"
        }, headers=headers)
        self.assertEqual(reg_res.status_code, 200)

        # Login with biometrics
        bio_login = self.client.post("/api/v1/auth/biometrics/login", json={
            "biometric_token": "bio_secure_enclave_key_456"
        })
        self.assertEqual(bio_login.status_code, 200)
        self.assertIn("access_token", bio_login.json())

if __name__ == "__main__":
    unittest.main()
