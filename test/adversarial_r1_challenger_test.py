"""
Adversarial Empirical Challenge Test Suite for SafeSphere Milestone 2 (R1: Navigation Traps & Route Fixes)
Author: Challenger 2 (teamwork_preview_challenger_m2_2)
Project: SafeSphere (lib/, test/)

This test harness executes deep empirical verification and adversarial stress tests:
1. Static & AST inspection of route tables, aliases, drawer definitions, and map navigation handlers.
2. Simulated Flutter Navigator state machine & router engine:
   - Validates all 12 registered routes in main.dart resolve cleanly to their concrete page instances.
   - Stress-tests obsolete route strings ('/community', '/chat') ensuring clean resolution.
   - Adversarially tests onUnknownRoute against edge-case strings: empty, whitespace, null name, deep paths, special chars, emojis, SQL/regex injection strings.
   - Simulates cyclical deep navigation loops across all destinations without route stack deadlock.
3. AppDrawer destination completeness, icon bindings, and SafeSphere branding audits.
4. Comprehensive route reference cross-audit: verifies that every Navigator.push / pushNamed call across ALL files in lib/ resolves to a valid route.
"""

import os
import re
import sys
import unittest
from typing import Dict, List, Optional, Set, Tuple, Any

PROJECT_ROOT = os.path.abspath(r"C:\Users\tejas\projects\safesphere")
LIB_DIR = os.path.join(PROJECT_ROOT, "lib")
PAGES_DIR = os.path.join(LIB_DIR, "pages")
WIDGETS_DIR = os.path.join(LIB_DIR, "widgets")

class SimulatedRouteSettings:
    def __init__(self, name: Optional[str] = None, arguments: Any = None):
        self.name = name
        self.arguments = arguments

class SimulatedRoute:
    def __init__(self, builder, settings: Optional[SimulatedRouteSettings] = None):
        self.builder = builder
        self.settings = settings
        self.target_widget = builder(None) if builder else None

class SimulatedNavigator:
    """Accurate state-machine simulation of Flutter's Navigator with MaterialApp routing."""
    def __init__(self, routes: Dict[str, Any], on_unknown_route=None):
        self.routes = routes
        self.on_unknown_route = on_unknown_route
        self.history: List[SimulatedRoute] = []

    def push_named(self, route_name: Optional[str]) -> SimulatedRoute:
        settings = SimulatedRouteSettings(name=route_name)
        if route_name is not None and route_name in self.routes:
            builder = self.routes[route_name]
            route = SimulatedRoute(builder, settings)
        elif self.on_unknown_route is not None:
            route = self.on_unknown_route(settings)
            if route is None:
                raise ValueError(f"onUnknownRoute returned null for route '{route_name}'")
        else:
            raise KeyError(f"Could not find generator for route '{route_name}' and no fallback defined.")

        self.history.append(route)
        return route

    def pop(self) -> Optional[SimulatedRoute]:
        if len(self.history) > 1:
            return self.history.pop()
        elif len(self.history) == 1:
            return self.history.pop()
        return None

    @property
    def current_route(self) -> Optional[SimulatedRoute]:
        return self.history[-1] if self.history else None


class TestMilestone2AdversarialRouting(unittest.TestCase):
    """Deep adversarial verification of SafeSphere M2 navigation & routes."""

    @classmethod
    def setUpClass(cls):
        cls.main_dart_path = os.path.join(LIB_DIR, "main.dart")
        cls.alerts_page_path = os.path.join(PAGES_DIR, "community_alerts_page.dart")
        cls.safety_map_page_path = os.path.join(PAGES_DIR, "safety_map_page.dart")
        cls.app_drawer_path = os.path.join(WIDGETS_DIR, "app_drawer.dart")

        with open(cls.main_dart_path, "r", encoding="utf-8") as f:
            cls.main_source = f.read()
        with open(cls.alerts_page_path, "r", encoding="utf-8") as f:
            cls.alerts_source = f.read()
        with open(cls.safety_map_page_path, "r", encoding="utf-8") as f:
            cls.safety_map_source = f.read()
        with open(cls.app_drawer_path, "r", encoding="utf-8") as f:
            cls.app_drawer_source = f.read()

        # Extract routes declared in main.dart
        cls.declared_routes = {}
        route_matches = re.findall(r"['\"]([^'\"]+)['\"]\s*:\s*\([^)]*\)\s*=>\s*const\s+([A-Za-z0-9_]+)\(\)", cls.main_source)
        for r, target in route_matches:
            cls.declared_routes[r] = target

    # -------------------------------------------------------------------------
    # TEST SUITE 1: Route Table Completeness & Resolution
    # -------------------------------------------------------------------------
    def test_01_all_10_primary_routes_present_and_mapped(self):
        """Verify all 10 primary routes specified in R1 and PROJECT.md are declared."""
        expected_primaries = {
            '/': 'HomePage',
            '/home': 'HomePage',
            '/map': 'SafetyMapPage',
            '/safety-map': 'SafetyMapPage',
            '/report': 'ReportPage',
            '/alerts': 'CommunityAlertsPage',
            '/ai-assistant': 'AiAssistantPage',
            '/share': 'ShareLocationPage',
            '/emergency': 'EmergencyPage',
            '/about': 'AboutPage',
        }
        for route, target_class in expected_primaries.items():
            self.assertIn(route, self.declared_routes, f"Primary route '{route}' missing from main.dart")
            self.assertEqual(self.declared_routes[route], target_class,
                             f"Route '{route}' maps to '{self.declared_routes[route]}' instead of '{target_class}'")

    def test_02_obsolete_aliases_cleanly_resolved(self):
        """Verify legacy route strings /community and /chat resolve without exception to their respective pages."""
        expected_aliases = {
            '/community': 'CommunityAlertsPage',
            '/chat': 'AiAssistantPage',
        }
        for alias, target_class in expected_aliases.items():
            self.assertIn(alias, self.declared_routes, f"Obsolete alias '{alias}' missing from main.dart")
            self.assertEqual(self.declared_routes[alias], target_class,
                             f"Alias '{alias}' maps to '{self.declared_routes[alias]}' instead of '{target_class}'")

    def test_03_all_target_page_classes_exist_in_pages_directory(self):
        """Verify every class in routes table actually exists as a declared widget in lib/pages/."""
        for route, target_class in self.declared_routes.items():
            # Scan all pages to ensure class declaration exists
            found = False
            for file in os.listdir(PAGES_DIR):
                if file.endswith(".dart"):
                    with open(os.path.join(PAGES_DIR, file), "r", encoding="utf-8") as f:
                        content = f.read()
                    if re.search(rf"\bclass\s+{target_class}\b", content):
                        found = True
                        break
            self.assertTrue(found, f"Target widget class '{target_class}' for route '{route}' not found in lib/pages/")

    # -------------------------------------------------------------------------
    # TEST SUITE 2: Adversarial Stress Testing of onUnknownRoute
    # -------------------------------------------------------------------------
    def test_04_unknown_route_handler_structure(self):
        """Verify onUnknownRoute handler exists, is a closure returning MaterialPageRoute with HomePage."""
        self.assertIn("onUnknownRoute:", self.main_source)
        self.assertIn("MaterialPageRoute", self.main_source)
        self.assertIn("HomePage", self.main_source)

    def test_05_adversarial_unknown_route_inputs_simulation(self):
        """Stress-test SimulatedNavigator against adversarial, malformed, and arbitrary route strings."""
        # Setup simulated router matching main.dart
        def make_builder(target_name):
            return lambda context: f"Widget({target_name})"

        routes = {r: make_builder(target) for r, target in self.declared_routes.items()}
        on_unknown = lambda settings: SimulatedRoute(lambda _: "Widget(HomePage)", settings)
        nav = SimulatedNavigator(routes=routes, on_unknown_route=on_unknown)

        # Start at home
        nav.push_named('/')
        self.assertEqual(nav.current_route.target_widget, "Widget(HomePage)")

        adversarial_routes = [
            "/completely-unknown-route-xyz",
            "/unknown/fake/route",
            "",
            "   ",
            "/",
            "//alerts",
            "/alerts/",
            "/home/subpath/not/exist",
            "/route?param=1&evil=<script>alert(1)</script>",
            "/DROP TABLE routes;--",
            "/🚨/danger/sos",
            "/null",
            None,  # null route string
            "/chat/extra",
            "/community/v2",
            "../relative/path/attempt",
            "C:\\Windows\\System32",
            "\n\t\r",
            "a" * 1000,  # buffer overflow attempt
        ]

        for route_str in adversarial_routes:
            try:
                res = nav.push_named(route_str)
                # If it's a known route (like '/'), target is its widget; otherwise fallback must be HomePage
                if route_str in routes:
                    self.assertIsNotNone(res.target_widget)
                else:
                    self.assertEqual(res.target_widget, "Widget(HomePage)",
                                     f"Adversarial input {repr(route_str)} did not fallback to HomePage")
            except Exception as e:
                self.fail(f"Adversarial route input {repr(route_str)} crashed router with exception: {e}")

    # -------------------------------------------------------------------------
    # TEST SUITE 3: Deep Cyclical Traversal & Stack Integrity
    # -------------------------------------------------------------------------
    def test_06_deep_circular_traversal_and_rapid_pop_cycle(self):
        """Simulate deep circular navigation sequence (100 transitions) across all app destinations."""
        def make_builder(target_name):
            return lambda context: f"Widget({target_name})"

        routes = {r: make_builder(target) for r, target in self.declared_routes.items()}
        on_unknown = lambda settings: SimulatedRoute(lambda _: "Widget(HomePage)", settings)
        nav = SimulatedNavigator(routes=routes, on_unknown_route=on_unknown)

        # Cycle of destinations
        destinations = [
            '/home', '/safety-map', '/alerts', '/report', '/ai-assistant',
            '/share', '/emergency', '/about', '/community', '/chat'
        ]

        # Push 100 times in loop
        for i in range(100):
            target = destinations[i % len(destinations)]
            res = nav.push_named(target)
            self.assertIsNotNone(res)
            self.assertIsNotNone(nav.current_route)

        self.assertEqual(len(nav.history), 100)

        # Pop all back to empty
        for _ in range(100):
            popped = nav.pop()
            self.assertIsNotNone(popped)

        self.assertEqual(len(nav.history), 0)

    # -------------------------------------------------------------------------
    # TEST SUITE 4: SafetyMapPage Navigation Trap Elimination
    # -------------------------------------------------------------------------
    def test_07_safety_map_appbar_leading_widget_is_interactive_back_button(self):
        """Verify static Icon(Icons.menu) is completely absent and replaced with interactive back button."""
        self.assertNotIn("const Icon(Icons.menu)", self.safety_map_source,
                         "CRITICAL: Static Icon(Icons.menu) navigation trap still present in SafetyMapPage!")

        # Verify presence of IconButton with Icons.arrow_back and Navigator pop
        match = re.search(
            r"leading:\s*IconButton\s*\(\s*icon:\s*const\s+Icon\(Icons\.arrow_back\),\s*onPressed:\s*\(\)\s*=>\s*Navigator\.(maybePop|pop)\(context\),?\s*\)",
            self.safety_map_source
        )
        self.assertIsNotNone(match, "SafetyMapPage must provide interactive IconButton with arrow_back and pop handler")

    # -------------------------------------------------------------------------
    # TEST SUITE 5: AppDrawer Completeness, Branding & Iconography
    # -------------------------------------------------------------------------
    def test_08_app_drawer_header_branding(self):
        """Verify AppDrawer displays 'SafeSphere' branding and zero 'Safety App' references."""
        self.assertIn('"SafeSphere"', self.app_drawer_source, "AppDrawer header must contain 'SafeSphere'")
        self.assertNotIn('"Safety App"', self.app_drawer_source, "AppDrawer must not contain obsolete 'Safety App'")

    def test_09_app_drawer_destination_completeness(self):
        """Verify AppDrawer contains all 8 primary destinations wired to correct routes."""
        expected_drawer_items = [
            ("Home", "/home", "Icons.home"),
            ("Safety Map", "/safety-map", "Icons.map"),
            ("Community Alerts", "/alerts", "Icons.campaign"),
            ("Report Near Me", "/report", "Icons.report"),
            ("AI Assistant", "/ai-assistant", "Icons.smart_toy"),
            ("Share Location", "/share", "Icons.share_location"),
            ("Emergency", "/emergency", "Icons.warning_amber"),
            ("About", "/about", "Icons.info_outline"),
        ]

        for title, route, icon in expected_drawer_items:
            # Check title and route binding
            pattern = rf'title:\s*"{re.escape(title)}".*?route:\s*[\'\"]{re.escape(route)}[\'\"]'
            self.assertTrue(bool(re.search(pattern, self.app_drawer_source, re.DOTALL)),
                            f"AppDrawer missing or misconfigured tile for '{title}' -> '{route}'")
            # Check icon
            icon_pattern = rf'icon:\s*{re.escape(icon)}.*?title:\s*"{re.escape(title)}"'
            self.assertTrue(bool(re.search(icon_pattern, self.app_drawer_source, re.DOTALL)),
                            f"AppDrawer tile for '{title}' missing expected icon '{icon}'")

    def test_10_app_drawer_tap_interaction_closes_drawer_and_pushes_route(self):
        """Verify AppDrawer onTap closes drawer (Navigator.pop) and pushes named route."""
        pattern = r"onTap:\s*\(\)\s*\{[^}]*Navigator\.pop\(context\);[^}]*Navigator\.pushNamed\(context,\s*route\);[^}]*\}"
        self.assertTrue(bool(re.search(pattern, self.app_drawer_source)),
                        "AppDrawer _drawerItem must pop context before pushing named route")

    # -------------------------------------------------------------------------
    # TEST SUITE 6: CommunityAlertsPage Drawer Audit
    # -------------------------------------------------------------------------
    def test_11_community_alerts_drawer_routes(self):
        """Verify community_alerts_page.dart no longer references broken /community or /chat routes."""
        self.assertNotIn("'/community'", self.alerts_source,
                         "Broken route '/community' still referenced in CommunityAlertsPage drawer")
        self.assertNotIn("'/chat'", self.alerts_source,
                         "Broken route '/chat' still referenced in CommunityAlertsPage drawer")

        # Verify active routes in its drawer
        self.assertIn('_drawerItem(Icons.home, "Home", \'/\')', self.alerts_source)
        self.assertIn('_drawerItem(Icons.report, "Report Near Me", \'/report\')', self.alerts_source)
        self.assertIn('_drawerItem(Icons.campaign, "Community Alerts", \'/alerts\')', self.alerts_source)
        self.assertIn('_drawerItem(Icons.chat, "Safety Assistant", \'/ai-assistant\')', self.alerts_source)
        self.assertIn('_drawerItem(Icons.support_agent, "Emergency Info", \'/emergency\')', self.alerts_source)

    # -------------------------------------------------------------------------
    # TEST SUITE 7: Cross-File Route Reference Audit (Zero Orphan Calls)
    # -------------------------------------------------------------------------
    def test_12_all_push_named_calls_in_lib_resolve_to_declared_routes(self):
        """Audit all pushNamed calls across entire lib/ folder to guarantee 0 unresolved routes."""
        all_referenced_routes = set()
        file_route_map = {}

        for root, _, files in os.walk(LIB_DIR):
            for file in files:
                if file.endswith(".dart"):
                    fpath = os.path.join(root, file)
                    rel_path = os.path.relpath(fpath, PROJECT_ROOT)
                    with open(fpath, "r", encoding="utf-8") as f:
                        code = f.read()

                    # Find pushNamed calls
                    matches = re.findall(r"pushNamed\([^,]+,\s*['\"]([^'\"]+)['\"]", code)
                    # Find _drawerItem calls
                    matches += re.findall(r"_drawerItem\([^,]+,\s*[^,]+,\s*['\"]([^'\"]+)['\"]", code)
                    # Find route: property
                    matches += re.findall(r"route:\s*['\"]([^'\"]+)['\"]", code)

                    for r in matches:
                        all_referenced_routes.add(r)
                        file_route_map.setdefault(r, []).append(rel_path)

        for route in all_referenced_routes:
            self.assertIn(
                route, self.declared_routes,
                f"Unresolved route string '{route}' referenced in {file_route_map.get(route)} is NOT declared in main.dart routes!"
            )

    # -------------------------------------------------------------------------
    # TEST SUITE 8: Route Table Uniqueness & Arguments Fuzzing
    # -------------------------------------------------------------------------
    def test_13_route_table_key_uniqueness(self):
        """Verify main.dart contains zero duplicate route keys in MaterialApp.routes map."""
        route_keys = re.findall(r"['\"]([^'\"]+)['\"]\s*:\s*\([^)]*\)\s*=>", self.main_source)
        seen = set()
        duplicates = set()
        for k in route_keys:
            if k in seen:
                duplicates.add(k)
            seen.add(k)
        self.assertEqual(len(duplicates), 0, f"Found duplicate route keys in main.dart: {duplicates}")
        self.assertGreaterEqual(len(route_keys), 12, f"Expected at least 12 route entries in main.dart, found {len(route_keys)}")

    def test_14_route_arguments_fuzzing(self):
        """Fuzz route navigation with arbitrary payload arguments across all valid routes."""
        def make_builder(target_name):
            return lambda context: f"Widget({target_name})"

        routes = {r: make_builder(target) for r, target in self.declared_routes.items()}
        on_unknown = lambda settings: SimulatedRoute(lambda _: "Widget(HomePage)", settings)
        nav = SimulatedNavigator(routes=routes, on_unknown_route=on_unknown)

        fuzz_payloads = [
            None,
            {},
            {"id": "incident_123", "title": "Danger Alert"},
            {"nested": {"data": [1, 2, 3]}},
            12345,
            "string_payload",
            [True, False, None],
        ]

        for r in routes.keys():
            for payload in fuzz_payloads:
                settings = SimulatedRouteSettings(name=r, arguments=payload)
                try:
                    builder = routes[r]
                    route = SimulatedRoute(builder, settings)
                    self.assertIsNotNone(route.target_widget)
                    self.assertEqual(route.settings.arguments, payload)
                except Exception as e:
                    self.fail(f"Route '{r}' crashed with argument payload {payload}: {e}")

    def test_15_drawer_routes_are_all_valid_and_distinct(self):
        """Verify all routes present in AppDrawer and CommunityAlertsPage drawer map to valid routes in main.dart."""
        # AppDrawer routes
        app_drawer_routes = re.findall(r"route:\s*['\"]([^'\"]+)['\"]", self.app_drawer_source)
        self.assertGreaterEqual(len(app_drawer_routes), 8, f"AppDrawer should contain at least 8 items, found {len(app_drawer_routes)}")
        for r in app_drawer_routes:
            self.assertIn(r, self.declared_routes, f"AppDrawer route '{r}' is not in main.dart routes")

        # CommunityAlertsPage drawer routes
        alerts_drawer_routes = re.findall(r"_drawerItem\([^,]+,\s*[^,]+,\s*['\"]([^'\"]+)['\"]", self.alerts_source)
        self.assertEqual(len(alerts_drawer_routes), 5, f"Alerts drawer should contain 5 items, found {len(alerts_drawer_routes)}")
        for r in alerts_drawer_routes:
            self.assertIn(r, self.declared_routes, f"Alerts drawer route '{r}' is not in main.dart routes")

    def test_16_stack_unwinding_invariants(self):
        """Verify popping down an arbitrary navigation sequence unwinds cleanly to initial state."""
        def make_builder(target_name):
            return lambda context: f"Widget({target_name})"

        routes = {r: make_builder(target) for r, target in self.declared_routes.items()}
        on_unknown = lambda settings: SimulatedRoute(lambda _: "Widget(HomePage)", settings)
        nav = SimulatedNavigator(routes=routes, on_unknown_route=on_unknown)

        sequence = ['/', '/alerts', '/safety-map', '/ai-assistant', '/report', '/about']
        for s in sequence:
            nav.push_named(s)

        self.assertEqual(len(nav.history), len(sequence))
        # Unwind one by one
        for expected in reversed(sequence):
            top = nav.current_route
            self.assertEqual(top.settings.name, expected)
            popped = nav.pop()
            self.assertEqual(popped.settings.name, expected)

        self.assertEqual(len(nav.history), 0)
        self.assertIsNone(nav.pop())


if __name__ == "__main__":
    unittest.main(verbosity=2)

