"""
SafeSphere Production Reliability & UX Enhancements Challenger Test Suite
Target: R1 (Emergency Alert Reliability), R2 (Auth & Session Resilience), R3 (Guardian Tracking Breadcrumb Trail)
Verifies: AST nodes, state machines, countdown timer, offline queue, SMS fallback, and breadcrumb rendering.
"""

import os
import re
import sys
import unittest
import asyncio
from typing import Dict, List, Optional, Any

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend")
LIB_DIR = os.path.join(FRONTEND_DIR, "lib")
SERVICES_DIR = os.path.join(LIB_DIR, "services")
PAGES_DIR = os.path.join(LIB_DIR, "pages")

AUTH_SERVICE_PATH = os.path.join(SERVICES_DIR, "auth_service.dart")
EMERGENCY_PAGE_PATH = os.path.join(PAGES_DIR, "emergency_page.dart")
TRACK_SESSION_PAGE_PATH = os.path.join(PAGES_DIR, "track_session_page.dart")


# ==============================================================================
# 1. AST & Static Code Analysis
# ==============================================================================

class TestProductionEnhancementsAST(unittest.TestCase):
    """Static AST and code invariant verification for R1, R2, and R3."""

    @classmethod
    def setUpClass(cls):
        with open(AUTH_SERVICE_PATH, "r", encoding="utf-8") as f:
            cls.auth_code = f.read()
        with open(EMERGENCY_PAGE_PATH, "r", encoding="utf-8") as f:
            cls.emergency_code = f.read()
        with open(TRACK_SESSION_PAGE_PATH, "r", encoding="utf-8") as f:
            cls.track_code = f.read()

    # --- R1: Emergency Alert Reliability ---
    def test_r1_countdown_dialog_ast(self):
        """Verify SosCountdownDialog exists with durationSeconds, Timer, and Cancel button."""
        self.assertIn("class SosCountdownDialog extends StatefulWidget", self.emergency_code)
        self.assertIn("final int durationSeconds;", self.emergency_code)
        self.assertIn("Timer? _timer;", self.emergency_code)
        self.assertIn("Timer.periodic(const Duration(seconds: 1)", self.emergency_code)
        self.assertIn("Cancel SOS", self.emergency_code)
        self.assertIn("_timer?.cancel()", self.emergency_code)

    def test_r1_sos_grace_window_wiring(self):
        """Verify countdown grace window dialog is invoked before SOS dispatch."""
        self.assertIn("_startSosGraceCountdownAndDispatch", self.emergency_code)
        self.assertIn("SosCountdownDialog(durationSeconds: 5)", self.emergency_code)
        self.assertIn("SOS alert cancelled.", self.emergency_code)
        self.assertIn("_executeSosDispatch", self.emergency_code)

    def test_r1_sms_fallback_intent(self):
        """Verify SMS fallback URI construction and launchUrl integration."""
        self.assertIn("Uri(", self.emergency_code)
        self.assertIn("scheme: 'sms'", self.emergency_code)
        self.assertIn("path: recipients", self.emergency_code)
        self.assertIn("queryParameters:", self.emergency_code)
        self.assertIn("await canLaunchUrl(smsUri)", self.emergency_code)
        self.assertIn("await launchUrl(smsUri", self.emergency_code)
        self.assertIn("Share.share(alertMsg)", self.emergency_code)

    def test_r1_sms_guardian_contact_extraction(self):
        """Verify emergency contact numbers are extracted from currentUser."""
        self.assertIn("currentUser?.emergencyContacts", self.emergency_code)
        self.assertIn("emergencyContactPhone", self.emergency_code)

    def test_r1_direct_sms_fallback_card(self):
        """Verify explicit direct SMS fallback option is present on emergency page."""
        self.assertIn("SMS Fallback SOS", self.emergency_code)
        self.assertIn("_triggerDirectSmsFallback", self.emergency_code)

    def test_r1_preserves_existing_helplines_and_emergency_call(self):
        """Ensure all prior helpline invariants and 112 dialing are strictly preserved."""
        self.assertIn('_makeCall(context, "112")', self.emergency_code)
        self.assertIn('"National Emergency", "112"', self.emergency_code)
        self.assertIn('"Women Helpline", "181"', self.emergency_code)
        self.assertIn('"Ambulance", "108"', self.emergency_code)
        self.assertIn('"Fire Services", "101"', self.emergency_code)
        self.assertRegex(self.emergency_code, r"Uri\(\s*scheme:\s*'tel',\s*path:\s*phoneNumber,?\s*\)")

    # --- R2: Authentication & Session Resilience ---
    def test_r2_in_flight_refresh_mutex(self):
        """Verify Future<String?>? _refreshFuture mutex for concurrent coalescing."""
        self.assertIn("Future<String?>? _refreshFuture;", self.auth_code)

    def test_r2_request_detailed_retry_parameter(self):
        """Verify _requestDetailed supports retryOn401 flag with termination guard."""
        self.assertIn("bool retryOn401 = true", self.auth_code)
        self.assertIn("statusCode == 401 && retryOn401", self.auth_code)
        self.assertIn("!path.startsWith('/api/v1/auth/')", self.auth_code)
        self.assertIn("retryOn401: false", self.auth_code)

    def test_r2_coalesced_refresh_invocation(self):
        """Verify 401 interception invokes refreshSession() via coalesced mutex."""
        self.assertIn("_refreshFuture ??= refreshSession().whenComplete(", self.auth_code)
        self.assertIn("_refreshFuture = null;", self.auth_code)

    def test_r2_offline_sos_queue_constants_and_methods(self):
        """Verify offline SOS storage key, queueing, and replay logic."""
        self.assertIn("keyOfflineSosQueue = 'safesphere_offline_sos_queue';", self.auth_code)
        self.assertIn("Future<void> queueOfflineSos(Map<String, dynamic> payload)", self.auth_code)
        self.assertIn("Future<List<Map<String, dynamic>>> getQueuedSosAlerts()", self.auth_code)
        self.assertIn("Future<int> processQueuedSosAlerts()", self.auth_code)
        self.assertIn("Future<void> clearQueuedSosAlerts()", self.auth_code)

    def test_r2_offline_sos_trigger_integration(self):
        """Verify triggerSos queues failed requests for resilience."""
        self.assertIn("await queueOfflineSos(body);", self.auth_code)

    # --- R3: Guardian Tracking Breadcrumb Trail ---
    def test_r3_breadcrumbs_state_declaration(self):
        """Verify _breadcrumbs list state is declared."""
        self.assertIn("final List<Map<String, dynamic>> _breadcrumbs = [];", self.track_code)

    def test_r3_ws_location_stream_update_appends_breadcrumbs(self):
        """Verify LOCATION_STREAM_UPDATE inserts incoming position into _breadcrumbs."""
        self.assertIn("_breadcrumbs.insert(0, {", self.track_code)
        self.assertIn("'latitude': _lat,", self.track_code)
        self.assertIn("'longitude': _lng,", self.track_code)

    def test_r3_apply_session_parses_breadcrumbs_array(self):
        """Verify _applySession ingests data['breadcrumbs'] and sorts reverse-chronologically."""
        self.assertIn("final crumbs = data['breadcrumbs'];", self.track_code)
        self.assertIn("_breadcrumbs.add(Map<String, dynamic>.from(c));", self.track_code)
        self.assertIn("tB.compareTo(tA)", self.track_code)

    def test_r3_breadcrumb_ui_rendering_precision(self):
        """Verify visual trail renders 5-decimal coordinates, timestamps, and accuracy badges."""
        self.assertIn("Recent Breadcrumb Trail", self.track_code)
        self.assertIn("toStringAsFixed(5)", self.track_code)
        self.assertIn("Time:", self.track_code)
        self.assertIn("toStringAsFixed(0)", self.track_code)
        self.assertIn("±", self.track_code)


# ==============================================================================
# 2. Behavioral Simulation Models & Oracles
# ==============================================================================

class SimulatedSosCountdown:
    """Simulates the 3-5 second SOS countdown grace state machine."""
    def __init__(self, duration_seconds: int = 5):
        self.duration_seconds = duration_seconds
        self.remaining = duration_seconds
        self.cancelled = False
        self.completed = False

    def tick(self):
        if self.cancelled or self.completed:
            return
        if self.remaining <= 1:
            self.remaining = 0
            self.completed = True
        else:
            self.remaining -= 1

    def cancel(self):
        if not self.completed:
            self.cancelled = True


class SimulatedOfflineQueue:
    """Simulates local storage queuing and network replay of SOS payloads."""
    def __init__(self):
        self.store: Dict[str, str] = {}
        self.key = "safesphere_offline_sos_queue"
        self.network_online = False
        self.replayed_alerts: List[Dict[str, Any]] = []

    def queue_offline_sos(self, payload: Dict[str, Any]):
        queue = self.get_queued()
        queue.append(payload)
        import json
        self.store[self.key] = json.dumps(queue)

    def get_queued(self) -> List[Dict[str, Any]]:
        import json
        raw = self.store.get(self.key)
        if not raw:
            return []
        return json.loads(raw)

    def process_queued(self) -> int:
        if not self.network_online:
            return 0
        queued = self.get_queued()
        processed = 0
        for item in queued:
            self.replayed_alerts.append(item)
            processed += 1
        self.store.pop(self.key, None)
        return processed


class SimulatedAuthMutex:
    """Simulates concurrent 401 handling with coalesced refresh mutex."""
    def __init__(self):
        self.refresh_calls = 0
        self.current_access_token = "token_v1_expired"
        self.valid_refresh_token = "refresh_v1"
        self.in_flight_refresh: Optional[asyncio.Future] = None

    async def refresh_session(self) -> str:
        self.refresh_calls += 1
        await asyncio.sleep(0.01)  # Simulate network latency
        self.current_access_token = f"token_v{self.refresh_calls + 1}_fresh"
        return self.current_access_token

    async def request_with_401_retry(self, path: str, token: str, retry_on_401: bool = True) -> Dict[str, Any]:
        # Simulate 401 if token is expired
        if token != self.current_access_token or "expired" in token:
            if retry_on_401:
                if self.in_flight_refresh is None:
                    loop = asyncio.get_event_loop()
                    self.in_flight_refresh = loop.create_task(self.refresh_session())
                try:
                    new_token = await self.in_flight_refresh
                finally:
                    self.in_flight_refresh = None
                return await self.request_with_401_retry(path, new_token, retry_on_401=False)
            return {"status": 401, "error": "UNAUTHORIZED"}
        return {"status": 200, "data": "success", "tokenUsed": token}


class TestBehavioralSimulations(unittest.TestCase):
    """Behavioral testing of state machines under asynchronous and error conditions."""

    def test_sos_countdown_cancelled_aborts_cleanly(self):
        """Countdown aborted at t=2s prevents SOS dispatch."""
        sm = SimulatedSosCountdown(duration_seconds=5)
        sm.tick()  # 4s
        sm.tick()  # 3s
        sm.cancel()
        sm.tick()
        self.assertTrue(sm.cancelled)
        self.assertFalse(sm.completed)
        self.assertGreater(sm.remaining, 0)

    def test_sos_countdown_completion_triggers_dispatch(self):
        """Countdown allowed to elapse to 0 triggers dispatch."""
        sm = SimulatedSosCountdown(duration_seconds=3)
        sm.tick()  # 2s
        sm.tick()  # 1s
        sm.tick()  # 0s -> completes
        self.assertFalse(sm.cancelled)
        self.assertTrue(sm.completed)
        self.assertEqual(sm.remaining, 0)

    def test_offline_sos_queue_and_replay(self):
        """Offline SOS queue stores failed alerts and replays all on reconnection."""
        queue = SimulatedOfflineQueue()
        alert1 = {"latitude": 28.6139, "longitude": 77.2090, "notes": "Alert 1"}
        alert2 = {"latitude": 28.6145, "longitude": 77.2095, "notes": "Alert 2"}

        queue.queue_offline_sos(alert1)
        queue.queue_offline_sos(alert2)
        self.assertEqual(len(queue.get_queued()), 2)

        # Attempt replay while still offline -> 0 processed
        count = queue.process_queued()
        self.assertEqual(count, 0)
        self.assertEqual(len(queue.get_queued()), 2)

        # Reconnect network and replay
        queue.network_online = True
        count = queue.process_queued()
        self.assertEqual(count, 2)
        self.assertEqual(len(queue.get_queued()), 0)
        self.assertEqual(len(queue.replayed_alerts), 2)

    def test_coalesced_refresh_mutex_single_call_on_concurrent_401(self):
        """Simultaneous 401 responses coalesce into exactly ONE refreshSession call."""
        async def run_concurrent():
            mutex = SimulatedAuthMutex()
            req1 = mutex.request_with_401_retry("/api/v1/sos/trigger", "token_v1_expired")
            req2 = mutex.request_with_401_retry("/api/v1/reports", "token_v1_expired")
            req3 = mutex.request_with_401_retry("/api/v1/markers", "token_v1_expired")

            res1, res2, res3 = await asyncio.gather(req1, req2, req3)

            # All 3 requests must succeed
            self.assertEqual(res1["status"], 200)
            self.assertEqual(res2["status"], 200)
            self.assertEqual(res3["status"], 200)

            # All 3 used the newly rotated token
            self.assertEqual(res1["tokenUsed"], "token_v2_fresh")
            self.assertEqual(res2["tokenUsed"], "token_v2_fresh")
            self.assertEqual(res3["tokenUsed"], "token_v2_fresh")

            # Exactly ONE refresh session was issued (no parallel token rotation)
            self.assertEqual(mutex.refresh_calls, 1)

        asyncio.run(run_concurrent())


if __name__ == "__main__":
    unittest.main()
