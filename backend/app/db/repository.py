import time
import math
from datetime import datetime
from typing import Dict, List, Optional
from ..models.schemas import (
    UserResponse, ReportResponse, SosResponse, MarkerResponse,
    ReportStatusEnum
)
from ..core.security import hash_password

class DataStore:
    def __init__(self):
        self.users: Dict[str, dict] = {}
        self.reports: Dict[str, dict] = {}
        self.sos_alerts: Dict[str, dict] = {}
        self.markers: Dict[str, dict] = {}
        self.share_sessions: Dict[str, dict] = {}
        self._seed_initial_data()

    def _seed_initial_data(self):
        # Seed default test user
        demo_user_id = "user_safesphere_demo_01"
        self.users[demo_user_id] = {
            "id": demo_user_id,
            "email": "demo@safesphere.org",
            "name": "Jane SafeSphere",
            "phone": "+91 9876543210",
            "password_hash": hash_password("SafeSphere@2026"),
            "pin": "1234",
            "biometric_token": "bio_device_demo_token_xyz987",
            "biometrics_enabled": True,
            "emergency_contacts": [
                {"name": "Emergency Services", "phone": "112", "relationship": "National Emergency"},
                {"name": "Family Contact", "phone": "+91 9876500001", "relationship": "Mother"}
            ],
            "is_active": True,
            "created_at": datetime.now().isoformat()
        }

        # Seed reports matching SafeSphere mobile state
        initial_reports = [
            {
                "id": "rep_1001",
                "type": "Theft",
                "description": "Bicycle reported stolen near Sector 18 Metro station bike rack.",
                "location": "Sector 18 Metro, Gate 2",
                "latitude": 28.5708,
                "longitude": 77.3271,
                "status": ReportStatusEnum.verified.value,
                "created_at": datetime.now().isoformat(),
                "reported_by": demo_user_id
            },
            {
                "id": "rep_1002",
                "type": "Harassment",
                "description": "Poorly lit underpass with groups loitering late evening.",
                "location": "North Ridge Underpass",
                "latitude": 28.6920,
                "longitude": 77.2150,
                "status": ReportStatusEnum.under_investigation.value,
                "created_at": datetime.now().isoformat(),
                "reported_by": demo_user_id
            },
            {
                "id": "rep_1003",
                "type": "Accident",
                "description": "Minor two-wheeler collision, emergency medical team dispatched.",
                "location": "Outer Ring Road Junction",
                "latitude": 28.6289,
                "longitude": 77.2065,
                "status": ReportStatusEnum.resolved.value,
                "created_at": datetime.now().isoformat(),
                "reported_by": demo_user_id
            }
        ]
        for rep in initial_reports:
            self.reports[rep["id"]] = rep

        # Seed safety markers (Police, Hospitals, Safe Zones)
        initial_markers = [
            {
                "id": "marker_police_cp",
                "name": "Connaught Place Central Police Post",
                "category": "Police Station",
                "latitude": 28.6315,
                "longitude": 77.2167,
                "address": "Inner Circle, Connaught Place, New Delhi",
                "is_verified": True,
                "created_at": datetime.now().isoformat()
            },
            {
                "id": "marker_hospital_aiims",
                "name": "AIIMS Emergency Trauma Care",
                "category": "Hospital",
                "latitude": 28.5672,
                "longitude": 77.2100,
                "address": "Ansari Nagar, New Delhi",
                "is_verified": True,
                "created_at": datetime.now().isoformat()
            },
            {
                "id": "marker_safe_delhi_hub",
                "name": "24/7 Women Transit Helpdesk & Safe Zone",
                "category": "Verified Safe Zone",
                "latitude": 28.6139,
                "longitude": 77.2090,
                "address": "Central Secretariat Metro, Gate 1",
                "is_verified": True,
                "created_at": datetime.now().isoformat()
            }
        ]
        for m in initial_markers:
            self.markers[m["id"]] = m

    def haversine_distance(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate great circle distance between two points in km."""
        R = 6371.0
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = (math.sin(dlat / 2) ** 2 +
             math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
             math.sin(dlon / 2) ** 2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return R * c

db = DataStore()
