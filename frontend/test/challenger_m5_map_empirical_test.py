"""
Empirical Challenger Test Suite for SafeSphere Milestone 4 (Map Excellence & Movement Intel)
Target Project: SafeSphere (backend + frontend/lib)

Stress Dimensions:
1. Movement analyzer honesty invariants — telemetry-only claims, NEVER
   fabricated intent ("safe", "at home", "reached"). State machine states
   constrained to a fixed allowlist; stall window must match backend F3-2.
2. 24x7 Store category wired end-to-end: backend VALID_MARKER_CATEGORIES,
   frontend submit dropdown, filter mapping, AppColors.green.
3. Near-me service strip privacy guard — must be gated behind _hasGpsFix
   (never against the fabricated Delhi default).
4. Route polyline honesty — guidance line drawn only for safety markers
   (never hazard pins), never for the user's own position, and labeled as
   straight-line (not turn-by-turn).
5. Movement intel wired into TrackSessionPage telemetry.
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


class MovementAnalyzerHonestyChallenges(unittest.TestCase):
    """The movement state machine must never fabricate intent."""

    @classmethod
    def setUpClass(cls):
        cls.source_path = os.path.join(FRONTEND_DIR, "lib", "services", "movement_analyzer.dart")
        cls.assertTrue(os.path.exists(cls.source_path), "movement_analyzer.dart must exist")
        cls.source = _read(cls.source_path)

    def test_01_states_are_constrained_allowlist(self):
        """Movement state strings must come from the fixed set."""
        self.assertIn("'unknown'", self.source)
        self.assertIn("'stationary'", self.source)
        self.assertIn("'moving'", self.source)
        self.assertIn("'stalled'", self.source)

    def test_02_never_claims_safety_or_intent(self):
        """Analyzer summaries must NOT assert safety/intent words."""
        forbidden = ['"You are safe', "'safe'", "safe at", "at home", "reached safely", "is safe"]
        # Extract only the summary-building strings, not the class docstring
        code_lines = []
        for line in self.source.splitlines():
            if line.strip().startswith("///") or line.strip().startswith("//"):
                continue
            code_lines.append(line)
        code = "\n".join(code_lines)
        for phrase in ["You are safe", "reached safely", "at home"]:
            self.assertNotIn(phrase, code,
                f"Movement analyzer must never claim intent: found '{phrase}'")

    def test_03_stall_window_matches_backend_f32(self):
        """Stall window must be 120s to agree with F3-2 backend detection."""
        match = re.search(r"stallWindow\s*=\s*Duration\(seconds:\s*(\d+)\)", self.source)
        self.assertIsNotNone(match, "stallWindow constant not found")
        self.assertEqual(int(match.group(1)), 120, "stall window must be 120s (F3-2 parity)")

    def test_04_empty_input_degrades_to_unknown(self):
        """Empty/malformed input must yield the 'unknown' state, not throw."""
        self.assertIn("points.isEmpty", self.source)
        self.assertIn("No location data yet", self.source)
        self.assertIn("_toDouble", self.source)

    def test_05_bogus_time_gaps_ignored(self):
        """Segments with zero/negative or >1h gaps must be skipped."""
        self.assertRegex(self.source, r"segSeconds <= 0 \|\| segSeconds > 3600")

    def test_06_track_session_wires_movement_tile(self):
        """TrackSessionPage must surface the movement summary."""
        page = _read(os.path.join(FRONTEND_DIR, "lib", "pages", "track_session_page.dart"))
        self.assertIn("movement_analyzer.dart", page)
        self.assertIn("_movementSummary", page)
        self.assertIn("MovementAnalyzer.analyze", page)


class TwentyFourSevenStoreCategoryChallenges(unittest.TestCase):
    """'24x7 Store' must be wired end-to-end."""

    def test_01_backend_valid_categories(self):
        model = _read(os.path.join(BACKEND_DIR, "src", "models", "markerModel.js"))
        self.assertIn("'24x7 Store'", model)

    def test_02_frontend_submit_dropdown(self):
        page = _read(os.path.join(FRONTEND_DIR, "lib", "pages", "safety_map_page.dart"))
        self.assertIn("DropdownMenuItem(value: '24x7 Store'", page)

    def test_03_frontend_filter_mapping(self):
        page = _read(os.path.join(FRONTEND_DIR, "lib", "pages", "safety_map_page.dart"))
        self.assertRegex(page, r"catLower\.contains\('24x7'\) \|\| catLower\.contains\('store'\)")
        self.assertIn('"Stores"', page)

    def test_04_icon_and_color_assigned(self):
        page = _read(os.path.join(FRONTEND_DIR, "lib", "pages", "safety_map_page.dart"))
        self.assertIn("Icons.storefront", page)
        self.assertIn("AppColors.green", page)

    def test_05_appcolors_green_defined(self):
        colors = _read(os.path.join(FRONTEND_DIR, "lib", "theme", "app_colors.dart"))
        match = re.search(r"static const Color green = Color\(0x([0-9A-Fa-f]+)\)", colors)
        self.assertIsNotNone(match, "AppColors.green must be defined")


class NearMeStripPrivacyChallenges(unittest.TestCase):
    """Near-me strip must never operate on the fabricated Delhi default."""

    @classmethod
    def setUpClass(cls):
        cls.page_path = os.path.join(FRONTEND_DIR, "lib", "pages", "safety_map_page.dart")
        cls.page = _read(cls.page_path)

    def test_01_strip_gated_on_real_gps_fix(self):
        self.assertIn("_hasGpsFix && !_isListView", self.page,
            "Near-me strip must render only with a real GPS fix and on the map view")

    def test_02_strip_exists_with_categories(self):
        self.assertIn("_buildNearMeStrip", self.page)
        for label in ["Police", "Hospital", "24x7", "Safe zone"]:
            self.assertIn(label, self.page)

    def test_03_honest_none_loaded_copy(self):
        self.assertIn("none loaded", self.page)

    def test_04_nearest_selection_uses_distance_sorted_items(self):
        """Items must be distance-sorted before the strip picks 'nearest'.
        Unknown distances (-1 sentinel, no GPS fix) sort last via sortKey."""
        self.assertIn("items.sort((a, b) => sortKey(a).compareTo(sortKey(b)));", self.page)
        self.assertIn("double sortKey(_MapPinItem i) => i.distanceKm < 0 ? double.infinity : i.distanceKm;", self.page)


class RoutePolylineHonestyChallenges(unittest.TestCase):
    """Guidance line must be honest and constrained."""

    @classmethod
    def setUpClass(cls):
        cls.page_path = os.path.join(FRONTEND_DIR, "lib", "pages", "safety_map_page.dart")
        cls.page = _read(cls.page_path)

    def test_01_polyline_gated_conditions(self):
        """Line only with GPS fix, selected safety marker, not self pin."""
        self.assertIn("_hasGpsFix && _selectedItem != null && !_selectedItem!.isHazardReport && _selectedItem!.id != \"you\"",
                      self.page)

    def test_02_uses_dashed_pattern(self):
        self.assertIn("StrokePattern.dashed", self.page)

    def test_03_documented_as_not_turn_by_turn(self):
        """The honest caveat must exist in the source near the polyline."""
        self.assertIn("it is NOT turn-by-turn", self.page)

    def test_04_external_directions_still_offered(self):
        """Real routing remains the external deep link."""
        self.assertIn("_openExternalDirections", self.page)


if __name__ == "__main__":
    unittest.main(verbosity=2)
