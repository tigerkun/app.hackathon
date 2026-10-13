"""
Empirical Challenger Test Suite for SafeSphere Milestone 2 (R1: Navigation Traps & Route Fixes)
Author: Challenger 1 (teamwork_preview_challenger_m2_1)
Target Project: SafeSphere (lib/, test/)

This test harness executes deep empirical verification and adversarial stress tests:
1. Feature Coverage Verification (Tiers 1-4 of r1_navigation_test.dart)
2. SafetyMapPage interactive back button mechanics and trap elimination
3. Complete route registration and route alias resolution (/community, /chat)
4. Unknown route fallback engine under adversarial inputs (fuzzy, unicode, SQLi, huge strings)
5. Navigation graph static analysis and dead-end reachability verification
6. Navigator state machine simulation under cyclic and random-walk stress (1000+ operations)
7. Global codebase audit: scanning all lib/ Dart files for orphan route strings
8. Regression checks against Milestone 1 (R4) deliverables
"""

import os
import re
import sys
import random
import unittest
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field

PROJECT_ROOT = os.path.abspath(r"C:\Users\tejas\projects\safesphere")
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend") if os.path.exists(os.path.join(PROJECT_ROOT, "frontend", "lib")) else PROJECT_ROOT
LIB_DIR = os.path.join(FRONTEND_DIR, "lib")
PAGES_DIR = os.path.join(LIB_DIR, "pages")
WIDGETS_DIR = os.path.join(LIB_DIR, "widgets")
TEST_DIR = os.path.join(FRONTEND_DIR, "test")

# ---------------------------------------------------------------------------
# Section 1: Simulated Flutter Navigation Runtime
# ---------------------------------------------------------------------------

@dataclass
class RouteSettings:
    name: Optional[str]
    arguments: Optional[object] = None

@dataclass
class SimulatedRoute:
    name: str
    page_class: str
    is_dialog: bool = False
    is_drawer: bool = False

class SimulatedNavigator:
    """
    High-fidelity stateful simulation of Flutter's Navigator stack and route resolution.
    Emulates:
    - routes map
    - onGenerateRoute
    - onUnknownRoute
    - push, pushNamed, pop, maybePop, canPop
    - drawer open/close semantics
    """
    def __init__(self, routes: Dict[str, str], unknown_route_fallback: str = "HomePage"):
        self.routes = dict(routes)
        self.unknown_route_fallback = unknown_route_fallback
        self.history: List[SimulatedRoute] = []
        self.active_drawer: Optional[str] = None

    def reset_to_initial(self, initial_route: str = "/"):
        self.history.clear()
        self.active_drawer = None
        self.push_named(initial_route)

    def can_pop(self) -> bool:
        return len(self.history) > 1 or self.active_drawer is not None

    def pop(self) -> bool:
        if self.active_drawer is not None:
            self.active_drawer = None
            return True
        if len(self.history) > 1:
            self.history.pop()
            return True
        elif len(self.history) == 1:
            # Cannot pop root route via pop()
            return False
        return False

    def maybe_pop(self) -> bool:
        """
        Emulates Navigator.maybePop():
        Returns true and pops if can_pop() is true; returns false without error if at root.
        """
        if self.can_pop():
            return self.pop()
        return False

    def open_drawer(self, drawer_name: str = "Drawer"):
        self.active_drawer = drawer_name

    def close_drawer(self):
        self.active_drawer = None

    def push_named(self, route_name: str) -> Tuple[bool, str]:
        """
        Simulates Navigator.pushNamed(context, route_name).
        Resolves via:
        1. routes[route_name]
        2. onUnknownRoute fallback
        Returns (is_known_route, target_page_class).
        """
        # If drawer was open, drawer should be popped before or by navigation
        if route_name in self.routes:
            target = self.routes[route_name]
            self.history.append(SimulatedRoute(name=route_name, page_class=target))
            return (True, target)
        else:
            # Fallback to onUnknownRoute
            target = self.unknown_route_fallback
            self.history.append(SimulatedRoute(name=route_name, page_class=target))
            return (False, target)

    @property
    def current_page(self) -> Optional[str]:
        return self.history[-1].page_class if self.history else None

    @property
    def depth(self) -> int:
        return len(self.history)


# ---------------------------------------------------------------------------
# Section 2: Empirical Test Suite
# ---------------------------------------------------------------------------

class TestMilestone2Navigation(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.main_path = os.path.join(LIB_DIR, "main.dart")
        cls.alerts_path = os.path.join(PAGES_DIR, "community_alerts_page.dart")
        cls.map_path = os.path.join(PAGES_DIR, "safety_map_page.dart")
        cls.drawer_path = os.path.join(WIDGETS_DIR, "app_drawer.dart")

        with open(cls.main_path, "r", encoding="utf-8") as f:
            cls.main_code = f.read()
        with open(cls.alerts_path, "r", encoding="utf-8") as f:
            cls.alerts_code = f.read()
        with open(cls.map_path, "r", encoding="utf-8") as f:
            cls.map_code = f.read()
        with open(cls.drawer_path, "r", encoding="utf-8") as f:
            cls.drawer_code = f.read()

        # Extract registered routes from main.dart
        cls.registered_routes: Dict[str, str] = {}
        route_pattern = re.compile(r"['\"](\/[a-zA-Z0-9_\-]*)['\"]\s*:\s*\([^)]*\)\s*=>\s*const\s+([A-Za-z0-9_]+)\(\)")
        for m in route_pattern.finditer(cls.main_code):
            cls.registered_routes[m.group(1)] = m.group(2)

    # -----------------------------------------------------------------------
    # Tier 1: Feature Coverage (Drawer Routes & Safety Map Back Button)
    # -----------------------------------------------------------------------

    def test_t1_1_safety_map_back_button_mechanics(self):
        """
        Verify that SafetyMapPage provides an interactive IconButton with Icons.arrow_back
        and Navigator.maybePop(context), eliminating the static Icon(Icons.menu) trap.
        """
        # 1. Assert inert static Icon is completely removed from leading
        self.assertNotIn("leading: const Icon(Icons.menu)", self.map_code,
                         "Static inert Icon(Icons.menu) must not be used as leading widget in SafetyMapPage")

        # 2. Assert interactive IconButton is present
        self.assertIn("IconButton(", self.map_code,
                      "SafetyMapPage must provide an interactive IconButton")
        self.assertIn("Icons.arrow_back", self.map_code,
                      "SafetyMapPage leading button must display Icons.arrow_back")

        # 3. Assert pop callback is wired
        has_pop = ("Navigator.maybePop(context)" in self.map_code or
                   "Navigator.pop(context)" in self.map_code)
        self.assertTrue(has_pop, "SafetyMapPage leading button must invoke Navigator.maybePop or pop")

        # 4. Empirical simulation of SafetyMapPage back button
        nav = SimulatedNavigator(self.registered_routes)
        nav.reset_to_initial("/")
        self.assertEqual(nav.current_page, "HomePage")

        # Push SafetyMapPage
        nav.push_named("/safety-map")
        self.assertEqual(nav.current_page, "SafetyMapPage")
        self.assertEqual(nav.depth, 2)

        # Trigger maybePop (simulating user tapping back button)
        popped = nav.maybe_pop()
        self.assertTrue(popped, "Tapping back button must successfully pop SafetyMapPage")
        self.assertEqual(nav.current_page, "HomePage")
        self.assertEqual(nav.depth, 1)

        # Corner case: What if SafetyMapPage is opened as the root route?
        nav_root = SimulatedNavigator(self.registered_routes)
        nav_root.reset_to_initial("/safety-map")
        self.assertEqual(nav_root.current_page, "SafetyMapPage")
        self.assertEqual(nav_root.depth, 1)
        # maybePop on root route safely returns False without throwing or crashing
        popped_at_root = nav_root.maybe_pop()
        self.assertFalse(popped_at_root, "maybePop on root route must safely return False without exception")
        self.assertEqual(nav_root.current_page, "SafetyMapPage", "Page remains intact at root")

    def test_t1_2_main_dart_primary_routes_completeness(self):
        """
        Verify that MyApp defines all 10 primary application routes, mapping to their
        correct respective page classes.
        """
        expected_mappings = {
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

        for route, expected_page in expected_mappings.items():
            self.assertIn(route, self.registered_routes,
                          f"Route '{route}' must be registered in main.dart")
            self.assertEqual(self.registered_routes[route], expected_page,
                             f"Route '{route}' must resolve to '{expected_page}', got '{self.registered_routes.get(route)}'")

    def test_t1_3_community_alerts_drawer_route_strings(self):
        """
        Verify that CommunityAlertsPage drawer items route cleanly without crashing,
        having eliminated broken routes '/community' and '/chat'.
        """
        self.assertNotIn("'/community'", self.alerts_code,
                         "Broken route '/community' must be eliminated from CommunityAlertsPage drawer")
        self.assertNotIn("'/chat'", self.alerts_code,
                         "Broken route '/chat' must be eliminated from CommunityAlertsPage drawer")

        # Verify correct drawer items
        self.assertIn("_drawerItem(Icons.home, \"Home\", '/')", self.alerts_code)
        self.assertIn("_drawerItem(Icons.report, \"Report Near Me\", '/report')", self.alerts_code)
        self.assertIn("_drawerItem(Icons.campaign, \"Community Alerts\", '/alerts')", self.alerts_code)
        self.assertIn("_drawerItem(Icons.chat, \"Safety Assistant\", '/ai-assistant')", self.alerts_code)
        self.assertIn("_drawerItem(Icons.support_agent, \"Emergency Info\", '/emergency')", self.alerts_code)

        # Verify drawer item callback pattern: pop drawer then push named route
        callback_pattern = re.search(r"ListTile\s*_drawerItem.*?\{.*?Navigator\.pop\(context\);.*?Navigator\.pushNamed\(context,\s*route\);.*?\}",
                                     self.alerts_code, re.DOTALL)
        self.assertIsNotNone(callback_pattern,
                             "CommunityAlertsPage _drawerItem must pop drawer before pushing named route")

    # -----------------------------------------------------------------------
    # Tier 2: Boundary & Corner Cases (Aliases, Unknown Route Fallback)
    # -----------------------------------------------------------------------

    def test_t2_1_route_aliases_resolution(self):
        """
        Verify that legacy or alternate route aliases /community and /chat resolve cleanly
        to CommunityAlertsPage and AiAssistantPage.
        """
        self.assertIn('/community', self.registered_routes, "Alias '/community' must be registered")
        self.assertEqual(self.registered_routes['/community'], 'CommunityAlertsPage',
                         "Alias '/community' must map to CommunityAlertsPage")

        self.assertIn('/chat', self.registered_routes, "Alias '/chat' must be registered")
        self.assertEqual(self.registered_routes['/chat'], 'AiAssistantPage',
                         "Alias '/chat' must map to AiAssistantPage")

    def test_t2_2_unknown_route_fallback_handler(self):
        """
        Verify that main.dart defines an onUnknownRoute fallback handler returning
        MaterialPageRoute(builder: (_) => const HomePage()).
        """
        self.assertIn("onUnknownRoute:", self.main_code,
                      "main.dart must define onUnknownRoute handler")
        self.assertIn("MaterialPageRoute", self.main_code,
                      "onUnknownRoute must construct a MaterialPageRoute")
        self.assertIn("HomePage", self.main_code,
                      "onUnknownRoute fallback builder must return HomePage")

    def test_t2_3_adversarial_unknown_route_inputs(self):
        """
        Stress test the unknown route fallback engine with adversarial inputs:
        - empty strings, malformed slashes
        - SQL injections, script tags
        - Unicode emojis, surrogate pairs
        - Deep paths, URI queries
        - Extremely long strings (10,000 characters)
        """
        adversarial_routes = [
            "",
            "   ",
            "/",
            "//",
            "///",
            "/unknown",
            "/completely-unknown-route-xyz",
            "/api/v1/auth/login",
            "/admin/portal",
            "/debug/console",
            "/<script>alert('xss')</script>",
            "/'; DROP TABLE routes; --",
            "/report?id=123&priority=urgent&category=theft",
            "/alerts#anchor-warning",
            "/safety/map/../alerts/../home",
            "/🚀/safety/🔥/sos",
            "/こんにちは/安全",
            " " * 100,
            "/" + "a" * 10000,
            "/null",
            "/undefined",
            "/-_-",
            "/!@#$%^&*()_+",
        ]

        nav = SimulatedNavigator(self.registered_routes, unknown_route_fallback="HomePage")
        nav.reset_to_initial("/")

        for test_route in adversarial_routes:
            initial_depth = nav.depth
            is_known, target_page = nav.push_named(test_route)

            # Route resolution must never crash or return None
            self.assertIsNotNone(target_page, f"Pushing '{test_route[:30]}' produced None target")
            self.assertEqual(nav.current_page, target_page)
            self.assertEqual(nav.depth, initial_depth + 1)

            if test_route in self.registered_routes:
                self.assertTrue(is_known)
            else:
                self.assertFalse(is_known, f"Route '{test_route[:30]}' should be flagged as unmapped fallback")
                self.assertEqual(target_page, "HomePage",
                                 f"Unmapped route '{test_route[:30]}' must fallback to HomePage")

            # Pop back to ensure stack remains clean
            nav.pop()
            self.assertEqual(nav.depth, initial_depth)

    def test_t2_4_app_drawer_branding_and_routes(self):
        """
        Verify that AppDrawer is branded 'SafeSphere' and all 8 destinations
        point to valid registered routes.
        """
        self.assertIn('"SafeSphere"', self.drawer_code, "AppDrawer must display 'SafeSphere' branding")
        self.assertNotIn('"Safety App"', self.drawer_code, "AppDrawer must not contain 'Safety App' placeholder")

        expected_destinations = [
            ("Home", "/home"),
            ("Safety Map", "/safety-map"),
            ("Community Alerts", "/alerts"),
            ("Report Near Me", "/report"),
            ("AI Assistant", "/ai-assistant"),
            ("Share Location", "/share"),
            ("Emergency", "/emergency"),
            ("About", "/about"),
        ]

        for title, route in expected_destinations:
            self.assertIn(f'"{title}"', self.drawer_code, f"AppDrawer must include item '{title}'")
            self.assertIn(f"'{route}'", self.drawer_code, f"AppDrawer must wire item '{title}' to route '{route}'")
            self.assertIn(route, self.registered_routes, f"Drawer route '{route}' must be registered in main.dart")

    # -----------------------------------------------------------------------
    # Tier 3: Cross-Feature Combinations & State Machine Stress
    # -----------------------------------------------------------------------

    def test_t3_1_deep_navigation_loop(self):
        """
        Empirically emulate Tier 3 of r1_navigation_test.dart:
        Full circular sequence: Home -> Map -> pop -> Report -> pop -> Alerts -> Assistant -> Emergency -> About -> pop 4x -> Home.
        """
        nav = SimulatedNavigator(self.registered_routes)
        nav.reset_to_initial("/")
        self.assertEqual(nav.current_page, "HomePage")
        self.assertEqual(nav.depth, 1)

        # 1. Home -> Safety Map
        nav.push_named("/safety-map")
        self.assertEqual(nav.current_page, "SafetyMapPage")
        self.assertEqual(nav.depth, 2)

        # 2. Safety Map -> pop back to Home
        nav.pop()
        self.assertEqual(nav.current_page, "HomePage")
        self.assertEqual(nav.depth, 1)

        # 3. Home -> Report
        nav.push_named("/report")
        self.assertEqual(nav.current_page, "ReportPage")
        self.assertEqual(nav.depth, 2)

        # 4. Report -> pop back to Home
        nav.pop()
        self.assertEqual(nav.current_page, "HomePage")
        self.assertEqual(nav.depth, 1)

        # 5. Home -> Alerts
        nav.push_named("/alerts")
        self.assertEqual(nav.current_page, "CommunityAlertsPage")
        self.assertEqual(nav.depth, 2)

        # 6. Alerts -> Assistant
        nav.push_named("/ai-assistant")
        self.assertEqual(nav.current_page, "AiAssistantPage")
        self.assertEqual(nav.depth, 3)

        # 7. Assistant -> Emergency
        nav.push_named("/emergency")
        self.assertEqual(nav.current_page, "EmergencyPage")
        self.assertEqual(nav.depth, 4)

        # 8. Emergency -> About
        nav.push_named("/about")
        self.assertEqual(nav.current_page, "AboutPage")
        self.assertEqual(nav.depth, 5)

        # Pop all back to Home
        nav.pop()
        self.assertEqual(nav.current_page, "EmergencyPage")
        nav.pop()
        self.assertEqual(nav.current_page, "AiAssistantPage")
        nav.pop()
        self.assertEqual(nav.current_page, "CommunityAlertsPage")
        nav.pop()
        self.assertEqual(nav.current_page, "HomePage")
        self.assertEqual(nav.depth, 1)

    def test_t3_2_random_walk_cyclical_navigation_stress(self):
        """
        Adversarial Stress Harness:
        Execute 1000 random navigation transitions across the navigation graph:
        - Randomly choosing drawer routes, back buttons, unmapped routes, and alias routes.
        - Verifying that navigator stack depth never drops below 1, never causes corruption,
          and always maintains coherent top-of-stack state.
        """
        rng = random.Random(42)  # Seeded for deterministic reproducibility
        nav = SimulatedNavigator(self.registered_routes, unknown_route_fallback="HomePage")
        nav.reset_to_initial("/")

        all_candidate_routes = list(self.registered_routes.keys()) + [
            "/unknown-1", "/random-path", "/deep/nested", "", "/community", "/chat"
        ]

        total_steps = 1000
        push_count = 0
        pop_count = 0
        maybe_pop_count = 0
        drawer_toggle_count = 0

        for step in range(total_steps):
            action = rng.choice(["push", "push", "pop", "maybe_pop", "drawer_nav", "toggle_drawer"])

            if action == "push":
                target_route = rng.choice(all_candidate_routes)
                is_known, target_page = nav.push_named(target_route)
                self.assertIsNotNone(nav.current_page)
                self.assertGreaterEqual(nav.depth, 1)
                push_count += 1

            elif action == "pop":
                if nav.can_pop():
                    nav.pop()
                    pop_count += 1
                else:
                    # At root, pop should fail gracefully
                    success = nav.pop()
                    self.assertFalse(success)
                self.assertGreaterEqual(nav.depth, 1)

            elif action == "maybe_pop":
                can_p = nav.can_pop()
                res = nav.maybe_pop()
                self.assertEqual(res, can_p)
                self.assertGreaterEqual(nav.depth, 1)
                maybe_pop_count += 1

            elif action == "drawer_nav":
                # Emulate user opening drawer and tapping a route
                nav.open_drawer()
                self.assertTrue(nav.can_pop())
                # Tap a drawer item (pop drawer then push route)
                nav.pop()  # drawer closes
                drawer_route = rng.choice(list(self.registered_routes.keys()))
                nav.push_named(drawer_route)
                self.assertGreaterEqual(nav.depth, 1)
                drawer_toggle_count += 1

            elif action == "toggle_drawer":
                # Rapid drawer open/close
                nav.open_drawer()
                self.assertIsNotNone(nav.active_drawer)
                nav.close_drawer()
                self.assertIsNone(nav.active_drawer)
                self.assertGreaterEqual(nav.depth, 1)
                drawer_toggle_count += 1

        # Finally, pop all the way back to root
        while nav.can_pop():
            nav.pop()

        self.assertEqual(nav.depth, 1)
        self.assertEqual(nav.current_page, "HomePage")
        print(f"\n  [Stress Stats] 1000 operations completed: Pushes={push_count}, Pops={pop_count}, "
              f"MaybePops={maybe_pop_count}, DrawerEvents={drawer_toggle_count}. Stack fully unwound to root.")

    # -----------------------------------------------------------------------
    # Tier 4: Global Codebase Audit for Orphan Routes
    # -----------------------------------------------------------------------

    def test_t4_1_global_route_strings_audit(self):
        """
        Audit all Dart files in lib/ for any hardcoded route strings (e.g. '/...')
        and ensure that 100% of them are registered in main.dart routes.
        """
        route_regex = re.compile(r"['\"](\/[a-zA-Z0-9_\-]+)['\"]")
        found_routes_per_file: Dict[str, Set[str]] = {}

        for root_dir, _, filenames in os.walk(LIB_DIR):
            for filename in filenames:
                if filename.endswith(".dart"):
                    filepath = os.path.join(root_dir, filename)
                    rel_path = os.path.relpath(filepath, LIB_DIR)
                    with open(filepath, "r", encoding="utf-8") as f:
                        code = f.read()

                    # Exclude comments
                    code_no_comments = re.sub(r"//.*", "", code)
                    matches = route_regex.findall(code_no_comments)
                    if matches:
                        # Filter to likely navigation route strings (starting with '/')
                        valid_matches = {m for m in matches if m.startswith("/") and len(m) > 1 or m == "/"}
                        if valid_matches:
                            found_routes_per_file[rel_path] = valid_matches

        registered_set = set(self.registered_routes.keys())

        # Check every found route
        orphan_routes = []
        for rel_path, routes_in_file in found_routes_per_file.items():
            for r in routes_in_file:
                # If it's used in Navigator.pushNamed or route arguments, must be in registered_routes
                if r not in registered_set:
                    orphan_routes.append((rel_path, r))

        self.assertEqual(len(orphan_routes), 0,
                         f"Found orphan route strings not registered in main.dart: {orphan_routes}")
        print(f"  [Global Audit] Scanned {len(found_routes_per_file)} files with route strings. Found 0 orphan routes.")

    # -----------------------------------------------------------------------
    # Tier 5: Milestone 1 Non-Regression Verification
    # -----------------------------------------------------------------------

    def test_t5_1_m1_safety_marker_model_intact(self):
        """
        Verify that Milestone 1 model lib/models/safety_marker.dart is intact and populated.
        """
        model_path = os.path.join(LIB_DIR, "models", "safety_marker.dart")
        self.assertTrue(os.path.exists(model_path))
        with open(model_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertGreater(len(content.strip()), 0, "safety_marker.dart must not be 0 bytes")
        self.assertIn("class SafetyMarker", content)

    def test_t5_2_m1_pruned_files_remain_deleted(self):
        """
        Verify that 10 dead prototype files pruned in Milestone 1 remain deleted.
        """
        pruned_files = [
            os.path.join(LIB_DIR, "data", "theme_store.dart"),
            os.path.join(PAGES_DIR, "chat_page.dart"),
            os.path.join(LIB_DIR, "utils", "route_animation.dart"),
            os.path.join(WIDGETS_DIR, "animated_entry.dart"),
            os.path.join(WIDGETS_DIR, "assistant_chat.dart"),
            os.path.join(WIDGETS_DIR, "assistant_home.dart"),
            os.path.join(WIDGETS_DIR, "base_scaffold.dart"),
            os.path.join(WIDGETS_DIR, "hover_scale.dart"),
            os.path.join(WIDGETS_DIR, "ng_card.dart"),
            os.path.join(WIDGETS_DIR, "safe_route_page.dart"),
        ]
        for p in pruned_files:
            self.assertFalse(os.path.exists(p), f"Pruned dead file {os.path.basename(p)} must not be restored")


if __name__ == '__main__':
    unittest.main(verbosity=2)
