"""
Empirical Challenger Test Suite for SafeSphere Milestone 6 (Hardening Sweep)
Target Project: SafeSphere (frontend/lib)

Stress Dimensions:
1. Offline SOS queue idempotency — content-signature dedupe must exist and
   must not dedupe distinct emergencies (float rounding bounded).
2. Multi-active-SOS resolve tokens — per-alert JSON map, capped, legacy key
   fallback, prune-on-resolve.
3. PIN file-fallback hashing — file fallback writes salted `sp1$` hashes,
   never the raw PIN; verification supports both legacy and hashed forms.
4. Tracking credential hygiene — TrackSessionPage keeps the session token
   in memory only (never persisted to any storage key).
5. Marker caps — backend rejects oversized name/address/note with 400.
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


class SosQueueIdempotencyChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.svc_path = os.path.join(FRONTEND_DIR, "lib", "services", "auth_service.dart")
        cls.svc = _read(cls.svc_path)

    def test_01_signature_dedupe_exists(self):
        self.assertIn("_sosQueueSignature", self.svc)
        self.assertIn("isDuplicate", self.svc)

    def test_02_signature_sorts_keys_and_rounds_floats(self):
        """Stable signature requires sorted keys and bounded float rounding."""
        match = re.search(r"String _sosQueueSignature[\s\S]*?^  \}", self.svc, re.M)
        self.assertIsNotNone(match, "_sosQueueSignature must exist")
        block = match.group(0)
        self.assertIn("..sort()", block)
        self.assertIn("toStringAsFixed(4)", block)

    def test_03_dupe_skip_returns_without_enqueue(self):
        self.assertRegex(self.svc, r"if \(isDuplicate\) return;")

    def test_04_queue_stamp_stripped_before_signature(self):
        """The signature compares the SOS body, not the _queuedAt stamp."""
        match = re.search(r"_sosQueueSignature\(Map<String, dynamic>\.from\(entry\)\.\.remove\('_queuedAt'\)\)",
                          self.svc)
        self.assertIsNotNone(match, "queued entries must be signature-checked WITHOUT the _queuedAt stamp")


class ResolveTokenMapChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.svc_path = os.path.join(FRONTEND_DIR, "lib", "services", "auth_service.dart")
        cls.svc = _read(cls.svc_path)

    def test_01_map_key_and_cap_defined(self):
        self.assertIn("safesphere_sos_resolve_tokens", self.svc)
        self.assertIn("maxResolveTokenMapSize", self.svc)

    def test_02_store_evicts_oldest_beyond_cap(self):
        self.assertIn("while (map.length > maxResolveTokenMapSize)", self.svc)
        self.assertIn("map.remove(map.keys.first)", self.svc)

    def test_03_read_falls_back_to_legacy_key(self):
        match = re.search(r"Future<String\?> _readResolveToken[\s\S]*?^  \}", self.svc, re.M)
        self.assertIsNotNone(match)
        self.assertIn("keyActiveSosResolveToken", match.group(0))

    def test_04_resolve_uses_per_alert_read_and_prunes(self):
        match = re.search(r"Future<bool> resolveSos[\s\S]*?^  \}", self.svc, re.M)
        self.assertIsNotNone(match)
        block = match.group(0)
        self.assertIn("_readResolveToken(targetId)", block)
        self.assertIn("_pruneResolveToken(targetId)", block)


class PinFileFallbackHashingChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.svc_path = os.path.join(FRONTEND_DIR, "lib", "services", "auth_service.dart")
        cls.svc = _read(cls.svc_path)

    def test_01_hashed_format_tagged(self):
        self.assertIn("sp1$", self.svc)
        self.assertIn("sha256", self.svc)

    def test_02_setpin_file_fallback_writes_hash(self):
        match = re.search(r"if \(!wroteSecure\) \{[\s\S]*?_hashPinForFile\(cleanPin\)", self.svc)
        self.assertIsNotNone(match, "file fallback must write the salted hash, not the raw PIN")

    def test_03_verify_supports_both_forms(self):
        self.assertIn("_matchesStoredPin", self.svc)
        match = re.search(r"bool _matchesStoredPin[\s\S]*?^  \}", self.svc, re.M)
        self.assertIsNotNone(match)
        self.assertIn("_isHashedPin", match.group(0))

    def test_04_legacy_plaintext_upgraded_in_place(self):
        """When secure storage is unavailable, legacy plaintext file values
        must be upgraded to hashed form during read-migration."""
        match = re.search(r"upgrade any LEGACY PLAINTEXT[\s\S]*?_hashPinForFile\(legacyPin\)", self.svc)
        self.assertIsNotNone(match)

    def test_05_never_locked_out(self):
        """Hash failure must degrade, not break verification entirely."""
        match = re.search(r"String _hashPinForFile[\s\S]*?^  \}", self.svc, re.M)
        self.assertIsNotNone(match)
        self.assertIn("catch (_)", match.group(0))


class TrackingCredentialHygieneChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.page_path = os.path.join(FRONTEND_DIR, "lib", "pages", "track_session_page.dart")
        cls.page = _read(cls.page_path)

    def test_01_session_token_in_memory_only(self):
        """The tracking token must never be persisted to any storage key."""
        self.assertNotRegex(self.page, r"(storage\.setString|SharedPreferences|\.setString\(.*(token|Token))",
                            "tracking token must not be written to persistent storage")
        self.assertIn("String? _sessionToken;", self.page)

    def test_02_clipboard_share_is_explicit_user_action(self):
        """The only token egress is the explicit copy-to-clipboard affordance."""
        self.assertIn("Clipboard.setData", self.page)


class MarkerCapsChallenges(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ctrl_path = os.path.join(BACKEND_DIR, "src", "controllers", "markerController.js")
        cls.ctrl = _read(cls.ctrl_path)

    def test_01_name_cap_80_rejected(self):
        self.assertIn("name must be 1-80 characters", self.ctrl)

    def test_02_address_cap_200_rejected(self):
        self.assertIn("address must be at most 200 characters", self.ctrl)

    def test_03_note_cap_500_rejected(self):
        self.assertIn("note must be at most 500 characters", self.ctrl)

    def test_04_backend_test_covers_caps(self):
        tests = _read(os.path.join(BACKEND_DIR, "tests", "reports_markers.test.js"))
        self.assertIn("M6: rejects oversized marker name", tests)
        self.assertIn("M6: rejects oversized marker address", tests)


class DisposeRaceSweepChallenges(unittest.TestCase):
    """Every awaited WebSocket.connect must guard against dispose-in-flight."""

    @classmethod
    def setUpClass(cls):
        cls.pages = [
            ("emergency_page.dart", os.path.join(FRONTEND_DIR, "lib", "pages", "emergency_page.dart")),
            ("share_location_page.dart", os.path.join(FRONTEND_DIR, "lib", "pages", "share_location_page.dart")),
            ("track_session_page.dart", os.path.join(FRONTEND_DIR, "lib", "pages", "track_session_page.dart")),
        ]

    def test_01_ws_connect_guarded_against_dispose(self):
        """Each WebSocket.connect await must close the socket if !mounted."""
        for name, path in self.pages:
            src = _read(path)
            self.assertIn("WebSocket.connect", src, f"{name} must connect a socket")
            # A guard must appear between the connect await and _ws assignment
            self.assertRegex(
                src,
                r"WebSocket\.connect[\s\S]{0,600}!mounted[\s\S]{0,600}ws\.close",
                f"{name}: WebSocket.connect must be followed by an !mounted ws.close() guard "
                "before _ws is assigned (otherwise dispose-in-flight leaks a listener)",
            )

    def test_02_my_circle_sheet_controller_disposed(self):
        """The Send-request sheet's TextEditingController must be disposed
        after the modal closes — otherwise every open leaks a controller."""
        page = _read(os.path.join(FRONTEND_DIR, "lib", "pages", "my_circle_page.dart"))
        # _showRequestDialog must be async and await+dispose the controller
        self.assertRegex(
            page,
            r"Future<void> _showRequestDialog[\s\S]*?await showModalBottomSheet[\s\S]*?controller\.dispose\(\)",
            "the sheet controller must be awaited-then-disposed in _showRequestDialog",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
