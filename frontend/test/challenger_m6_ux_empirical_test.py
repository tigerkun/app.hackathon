"""
Empirical Challenger Test Suite for SafeSphere Milestone 5 (UX Polish: Privacy Hub & WhatsApp SOS)
Target Project: SafeSphere (backend + frontend/lib)

Stress Dimensions:
1. Privacy Hub ("Who can see me") — every claim must come from live server
   data; no fabricated visibility; honest offline copy; route is
   authenticated-only; Safe ID presence must be tolerant to null.
2. WhatsApp SOS share — fresh GPS fix required, honest no-GPS copy (never
   fake coordinates), universal wa.me scheme, system share sheet fallback.
3. sessions/mine token scrub — backend must never echo the tracking token.
4. Drawer & route wiring — privacy hub reachable for authenticated users.
"""

import os
import re
import unittest

PROJECT_ROOT = os.path.abspath(r"C:\Users\tejas\projects\safesphere")
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend") if os.path.exists(os.path.join(PROJECT_ROOT, "frontend", "lib")) else PROJECT_ROOT
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")


def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


class PrivacyHubChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.page_path = os.path.join(FRONTEND_DIR, "lib", "pages", "privacy_hub_page.dart")
        cls.assertTrue(os.path.exists(cls.page_path), "privacy_hub_page.dart must exist")
        cls.page = _read(cls.page_path)

    def test_01_every_section_derived_from_live_data(self):
        """Must call both live data sources, never hardcode visibility."""
        self.assertIn("fetchMyTrackingSessions", self.page)
        self.assertIn("fetchMyConnections", self.page)

    def test_02_honest_offline_copy(self):
        """Offline state must say the page only shows what's true NOW."""
        self.assertIn("only shows what's true right now", self.page)

    def test_03_empty_states_plain_language(self):
        self.assertIn("No live trips. Your location is not streaming to anyone.", self.page)
        self.assertIn("Nobody can see your location or status.", self.page)

    def test_04_pending_requests_expose_nothing(self):
        self.assertIn("they can see NOTHING until you accept", self.page)

    def test_05_safe_id_tolerant_to_null(self):
        """Safe ID display must tolerate a null/stale profile explicitly."""
        self.assertIn("_safeId != null && _safeId!.isNotEmpty", self.page)
        self.assertIn("unavailable — check your connection", self.page)

    def test_06_revoke_is_immediate_and_surfaced(self):
        self.assertIn("revokeConnection", self.page)
        self.assertIn("Access removed immediately.", self.page)

    def test_07_no_fake_success_paths(self):
        """Page must surface server error strings, not fabricate success."""
        self.assertNotIn("success: true", self.page.replace(
            "res['ok'] == true", "").replace("_load();", ""))


class WhatsAppSosShareChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.page_path = os.path.join(FRONTEND_DIR, "lib", "pages", "emergency_page.dart")
        cls.page = _read(cls.page_path)

    def test_01_whatsapp_button_is_first_class(self):
        self.assertIn("Share via WhatsApp", self.page)
        self.assertIn("0xFF25D366", self.page)

    def test_02_fresh_gps_fix_required(self):
        """The share pulls a NEW Geolocator.getCurrentPosition, not stale state."""
        self.assertRegex(self.page, r"_shareSosViaWhatsApp[\s\S]{0,2000}Geolocator\.getCurrentPosition")

    def test_03_no_gps_honest_copy(self):
        self.assertIn("Could not get GPS fix", self.page)
        self.assertIn("do not assume my location", self.page)

    def test_04_wa_me_universal_scheme(self):
        self.assertIn("https://wa.me/?text=", self.page)

    def test_05_system_share_fallback(self):
        """If WhatsApp is unavailable, the system share sheet is the fallback."""
        self.assertIn("Share.share(buffer.toString())", self.page)


class SessionsMineScrubChallenges(unittest.TestCase):
    def test_01_token_never_in_response(self):
        ctrl = _read(os.path.join(BACKEND_DIR, "src", "controllers", "locationController.js"))
        # The map block for listMine must not pass through s.token
        match = re.search(r"function listMine[\s\S]*?activeSessions: sessions", ctrl)
        self.assertIsNotNone(match, "listMine handler must exist")
        block = match.group(0)
        self.assertNotRegex(block, r"token:\s*s\.token",
                            "listMine must not echo the raw tracking token")

    def test_02_route_requires_auth(self):
        routes = _read(os.path.join(BACKEND_DIR, "src", "routes", "locationRoutes.js"))
        self.assertRegex(routes, r"router\.get\('/sessions/mine',\s*requireAuth")

    def test_03_route_declared_before_track_param(self):
        """/sessions/mine must not be shadowed by /track/:sessionId."""
        routes = _read(os.path.join(BACKEND_DIR, "src", "routes", "locationRoutes.js"))
        self.assertLess(routes.index("/sessions/mine"), routes.index("/track/:sessionId"))


class WiringChallenges(unittest.TestCase):
    def test_01_route_registered(self):
        main = _read(os.path.join(FRONTEND_DIR, "lib", "main.dart"))
        self.assertIn("'/privacy-hub': (_) => const PrivacyHubPage()", main)

    def test_02_guard_protects_route(self):
        guard = _read(os.path.join(FRONTEND_DIR, "lib", "routes", "route_guard.dart"))
        self.assertIn("AppRoutes.privacyHub", guard)

    def test_03_drawer_entry_authenticated_only(self):
        drawer = _read(os.path.join(FRONTEND_DIR, "lib", "widgets", "app_drawer.dart"))
        self.assertIn("Who can see me", drawer)
        self.assertIn("if (authState.isAuthenticated)", drawer)

    def test_04_service_method_exists(self):
        svc = _read(os.path.join(FRONTEND_DIR, "lib", "services", "auth_service.dart"))
        self.assertIn("fetchMyTrackingSessions", svc)
        self.assertIn("'/api/v1/location/sessions/mine'", svc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
