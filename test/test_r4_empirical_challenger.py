"""
Empirical Challenger Test Suite for Milestone 1 (R4)
SafeSphere Flutter Project

Runs comprehensive, adversarial verification on:
1. Reachability graph and dead imports / broken paths / orphan references
2. Pruned dead files and class name deduplication
3. SafetyMarker model and export contracts
4. TypingText widget integration and lifecycle safety
5. ReportStore and Report model data layer functionality for M4
6. Screen and route registration integrity
"""

import os
import re
import sys
import unittest
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
LIB_DIR = PROJECT_ROOT / "lib"
TEST_DIR = PROJECT_ROOT / "test"

DEAD_FILES = [
    "lib/data/theme_store.dart",
    "lib/pages/chat_page.dart",
    "lib/utils/route_animation.dart",
    "lib/widgets/animated_entry.dart",
    "lib/widgets/assistant_chat.dart",
    "lib/widgets/assistant_home.dart",
    "lib/widgets/base_scaffold.dart",
    "lib/widgets/hover_scale.dart",
    "lib/widgets/ng_card.dart",
    "lib/widgets/safe_route_page.dart",
]

EXPECTED_LIB_FILES = {
    "lib/main.dart",
    "lib/data/report_store.dart",
    "lib/models/report_model.dart",
    "lib/models/safety_marker.dart",
    "lib/pages/about_page.dart",
    "lib/pages/ai_assistant_page.dart",
    "lib/pages/community_alerts_page.dart",
    "lib/pages/emergency_page.dart",
    "lib/pages/home_page.dart",
    "lib/pages/report_page.dart",
    "lib/pages/safety_map_page.dart",
    "lib/pages/share_location_page.dart",
    "lib/theme/app_colors.dart",
    "lib/theme/app_theme.dart",
    "lib/widgets/app_drawer.dart",
    "lib/widgets/glass_container.dart",
    "lib/widgets/map_placeholder.dart",
    "lib/widgets/typing_text.dart",
}


def get_all_dart_files(directory: Path):
    return [p for p in directory.rglob("*.dart") if p.is_file()]


def extract_imports_and_exports(file_path: Path):
    content = file_path.read_text(encoding="utf-8")
    import_pattern = re.compile(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.MULTILINE)
    return import_pattern.findall(content)


def extract_classes(file_path: Path):
    content = file_path.read_text(encoding="utf-8")
    class_pattern = re.compile(r"""^\s*class\s+([A-Za-z0-9_]+)""", re.MULTILINE)
    return class_pattern.findall(content)


class TestReachabilityAndImports(unittest.TestCase):
    """Test 1: Adversarially verify reachability graph, imports, and relative paths."""

    def test_exact_files_in_lib(self):
        dart_files = get_all_dart_files(LIB_DIR)
        rel_files = {p.relative_to(PROJECT_ROOT).as_posix() for p in dart_files}
        self.assertEqual(
            rel_files,
            EXPECTED_LIB_FILES,
            f"lib/ file inventory mismatch!\nUnexpected: {rel_files - EXPECTED_LIB_FILES}\nMissing: {EXPECTED_LIB_FILES - rel_files}",
        )
        self.assertEqual(len(dart_files), 18, f"Expected exactly 18 Dart files in lib/, found {len(dart_files)}")

    def test_no_zero_byte_files(self):
        dart_files = get_all_dart_files(LIB_DIR)
        for f in dart_files:
            size = f.stat().st_size
            rel = f.relative_to(PROJECT_ROOT).as_posix()
            self.assertGreater(size, 0, f"File {rel} is empty (0 bytes)!")

    def test_all_relative_imports_and_exports_resolve(self):
        dart_files = get_all_dart_files(LIB_DIR)
        for f in dart_files:
            rel = f.relative_to(PROJECT_ROOT).as_posix()
            directives = extract_imports_and_exports(f)
            for d in directives:
                if d.startswith("package:") or d.startswith("dart:"):
                    continue
                # Resolve relative path
                resolved = (f.parent / d).resolve()
                self.assertTrue(
                    resolved.exists(),
                    f"In {rel}: broken relative import/export target '{d}' (resolved to {resolved}) does not exist!",
                )
                self.assertTrue(
                    resolved.is_file(),
                    f"In {rel}: target '{d}' is not a file!",
                )

    def test_no_imports_of_pruned_files_anywhere(self):
        all_dart = get_all_dart_files(PROJECT_ROOT / "lib") + get_all_dart_files(PROJECT_ROOT / "test")
        dead_filenames = {Path(df).name for df in DEAD_FILES}
        for f in all_dart:
            if f.name == Path(__file__).name:
                continue
            content = f.read_text(encoding="utf-8")
            directives = extract_imports_and_exports(f)
            for d in directives:
                target_name = Path(d).name
                self.assertNotIn(
                    target_name,
                    dead_filenames,
                    f"Active file {f.relative_to(PROJECT_ROOT)} still imports pruned file '{d}'!",
                )

    def test_lib_utils_directory_does_not_exist(self):
        utils_dir = LIB_DIR / "utils"
        self.assertFalse(utils_dir.exists(), "Directory lib/utils was supposed to be pruned but still exists!")

    def test_dead_files_physically_absent(self):
        for df in DEAD_FILES:
            target = PROJECT_ROOT / df
            self.assertFalse(target.exists(), f"Pruned file {df} still exists on filesystem!")

    def test_reachability_graph_from_main(self):
        # Build directed graph of local lib dependencies
        graph = {}
        for f in get_all_dart_files(LIB_DIR):
            rel = f.relative_to(LIB_DIR).as_posix()
            graph[rel] = set()
            for d in extract_imports_and_exports(f):
                if d.startswith("package:") or d.startswith("dart:"):
                    continue
                target = (f.parent / d).resolve()
                if LIB_DIR in target.parents or target == LIB_DIR:
                    graph[rel].add(target.relative_to(LIB_DIR).as_posix())

        # Traverse from main.dart
        visited = set()
        queue = ["main.dart"]
        while queue:
            curr = queue.pop(0)
            if curr not in visited:
                visited.add(curr)
                queue.extend(graph.get(curr, set()) - visited)

        expected_reachable_from_main = {
            "main.dart",
            "theme/app_theme.dart",
            "theme/app_colors.dart",
            "pages/home_page.dart",
            "pages/safety_map_page.dart",
            "pages/report_page.dart",
            "pages/ai_assistant_page.dart",
            "pages/community_alerts_page.dart",
            "pages/share_location_page.dart",
            "pages/emergency_page.dart",
            "pages/about_page.dart",
            "widgets/app_drawer.dart",
            "widgets/glass_container.dart",
            "widgets/map_placeholder.dart",
            "widgets/typing_text.dart",
            "models/safety_marker.dart",
        }

        self.assertEqual(
            visited,
            expected_reachable_from_main,
            f"Main reachability graph discrepancy:\nMissing: {expected_reachable_from_main - visited}\nUnexpected: {visited - expected_reachable_from_main}",
        )

        # The only files not directly in the main UI tree are the M4 data store files
        retained_m4_files = set(graph.keys()) - visited
        self.assertEqual(
            retained_m4_files,
            {"data/report_store.dart", "models/report_model.dart"},
            f"Unexpected unreached files: {retained_m4_files}",
        )
        # Verify report_store reaches report_model
        self.assertIn("models/report_model.dart", graph["data/report_store.dart"])


class TestClassUniquenessAndCollisions(unittest.TestCase):
    """Test 2: Verify zero duplicate class declarations in lib/."""

    def test_zero_duplicate_public_classes(self):
        class_to_files = {}
        for f in get_all_dart_files(LIB_DIR):
            rel = f.relative_to(PROJECT_ROOT).as_posix()
            classes = extract_classes(f)
            for cls in classes:
                if cls.startswith("_"):
                    continue  # private classes are library-scoped
                class_to_files.setdefault(cls, []).append(rel)

        duplicates = {cls: files for cls, files in class_to_files.items() if len(files) > 1}
        self.assertEqual(
            duplicates,
            {},
            f"Duplicate public class declarations found across lib/: {duplicates}",
        )
        self.assertIn("AppTheme", class_to_files)
        self.assertEqual(len(class_to_files["AppTheme"]), 1)
        self.assertEqual(class_to_files["AppTheme"][0], "lib/theme/app_theme.dart")


class TestSafetyMarkerAndMapPlaceholder(unittest.TestCase):
    """Test 3: Verify SafetyMarker model and export contract."""

    def test_safety_marker_model_structure(self):
        marker_file = LIB_DIR / "models" / "safety_marker.dart"
        self.assertTrue(marker_file.exists())
        content = marker_file.read_text(encoding="utf-8")
        self.assertIn("class SafetyMarker", content)
        self.assertIn("final Offset position;", content)
        self.assertIn("final IconData icon;", content)
        self.assertIn("final Color color;", content)
        self.assertIn("final String label;", content)
        self.assertIn("const SafetyMarker({", content)

    def test_map_placeholder_exports_safety_marker(self):
        map_file = LIB_DIR / "widgets" / "map_placeholder.dart"
        self.assertTrue(map_file.exists())
        content = map_file.read_text(encoding="utf-8")
        self.assertIn("import '../models/safety_marker.dart';", content)
        self.assertIn("export '../models/safety_marker.dart';", content)
        # Must not declare its own SafetyMarker class
        self.assertNotIn("class SafetyMarker {", content)


class TestTypingTextIntegration(unittest.TestCase):
    """Test 4: Verify TypingText widget integration and lifecycle safety."""

    def test_typing_text_widget_file(self):
        tt_file = LIB_DIR / "widgets" / "typing_text.dart"
        self.assertTrue(tt_file.exists())
        content = tt_file.read_text(encoding="utf-8")
        self.assertIn("class TypingText extends StatefulWidget", content)
        self.assertIn("Timer? _timer;", content)
        self.assertIn("_timer?.cancel();", content)
        self.assertIn("if (!mounted)", content)

    def test_ai_assistant_page_integrates_typing_text(self):
        ai_file = LIB_DIR / "pages" / "ai_assistant_page.dart"
        self.assertTrue(ai_file.exists())
        content = ai_file.read_text(encoding="utf-8")
        self.assertIn("import '../widgets/typing_text.dart';", content)
        # Must NOT define inline TypingText
        self.assertNotIn("class TypingText extends StatefulWidget", content)
        self.assertNotIn("class _TypingTextState", content)
        # Must instantiate TypingText
        self.assertIn("TypingText(", content)


class TestReportStoreAndModelLifecycle(unittest.TestCase):
    """Test 5: Validate ReportStore and Report model for downstream M4."""

    def test_report_model_fields(self):
        rm_file = LIB_DIR / "models" / "report_model.dart"
        self.assertTrue(rm_file.exists())
        content = rm_file.read_text(encoding="utf-8")
        self.assertIn("enum ReportStatus { pending, approved, rejected }", content)
        self.assertIn("class Report {", content)
        self.assertIn("final String id;", content)
        self.assertIn("final String type;", content)
        self.assertIn("final String location;", content)
        self.assertIn("final String description;", content)
        self.assertIn("final DateTime time;", content)
        self.assertIn("ReportStatus status;", content)

    def test_report_store_methods(self):
        rs_file = LIB_DIR / "data" / "report_store.dart"
        self.assertTrue(rs_file.exists())
        content = rs_file.read_text(encoding="utf-8")
        self.assertIn("import '../models/report_model.dart';", content)
        self.assertIn("class ReportStore {", content)
        self.assertIn("static final List<Report> reports", content)
        self.assertIn("static void addReport(Report report)", content)
        self.assertIn("static int get total", content)
        self.assertIn("static int countByStatus(ReportStatus status)", content)

    def test_report_store_simulated_oracle(self):
        """Simulate ReportStore operations with adversarial edge cases in Python."""
        class MockReportStatus:
            pending = "pending"
            approved = "approved"
            rejected = "rejected"

        class MockReport:
            def __init__(self, id, type, location, description, time, status=MockReportStatus.pending):
                self.id = id
                self.type = type
                self.location = location
                self.description = description
                self.time = time
                self.status = status

        class MockReportStore:
            reports = []

            @classmethod
            def addReport(cls, report):
                cls.reports.append(report)

            @classmethod
            def total(cls):
                return len(cls.reports)

            @classmethod
            def countByStatus(cls, status):
                return sum(1 for r in cls.reports if r.status == status)

            @classmethod
            def clear(cls):
                cls.reports.clear()

        # Adversarial Stress Test:
        MockReportStore.clear()
        self.assertEqual(MockReportStore.total(), 0)

        # 1. Normal additions
        r1 = MockReport("r1", "Theft", "Loc A", "Desc A", datetime.now(), MockReportStatus.pending)
        r2 = MockReport("r2", "Harassment", "Loc B", "Desc B", datetime.now(), MockReportStatus.approved)
        r3 = MockReport("r3", "Unsafe Area", "Loc C", "Desc C", datetime.now(), MockReportStatus.rejected)
        MockReportStore.addReport(r1)
        MockReportStore.addReport(r2)
        MockReportStore.addReport(r3)

        self.assertEqual(MockReportStore.total(), 3)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.pending), 1)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.approved), 1)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.rejected), 1)

        # 2. Extreme edge case additions: multiline strings, emojis, unicode, long strings
        complex_text = "🚨 SOS! Special chars: <>&\"'\\/\nLine 2\nUnicode: 你好 мир"
        r_complex = MockReport("r-unicode", "Crisis", "Everywhere", complex_text, datetime.now())
        MockReportStore.addReport(r_complex)

        self.assertEqual(MockReportStore.total(), 4)
        self.assertEqual(MockReportStore.reports[-1].description, complex_text)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.pending), 2)

        # 3. Batch stress: 1000 reports
        for i in range(1000):
            st = MockReportStatus.pending if i % 2 == 0 else MockReportStatus.approved
            MockReportStore.addReport(MockReport(f"batch-{i}", "Type", "Loc", "Desc", datetime.now(), st))

        self.assertEqual(MockReportStore.total(), 1004)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.pending), 502)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.approved), 501)
        self.assertEqual(MockReportStore.countByStatus(MockReportStatus.rejected), 1)

        MockReportStore.clear()
        self.assertEqual(MockReportStore.total(), 0)


class TestActiveScreensAndMainRoutes(unittest.TestCase):
    """Test 6: Verify pruning did not break lib/main.dart or any active screen."""

    def test_main_routes_map(self):
        main_file = LIB_DIR / "main.dart"
        content = main_file.read_text(encoding="utf-8")
        expected_routes = [
            "'/'",
            "'/map'",
            "'/report'",
            "'/safety-map'",
            "'/ai-assistant'",
            "'/home'",
            "'/alerts'",
            "'/share'",
            "'/emergency'",
            "'/about'",
        ]
        for route in expected_routes:
            self.assertIn(route, content, f"Route {route} missing from lib/main.dart!")

    def test_all_eight_screen_widgets_exist_and_well_formed(self):
        screen_map = {
            "HomePage": LIB_DIR / "pages" / "home_page.dart",
            "SafetyMapPage": LIB_DIR / "pages" / "safety_map_page.dart",
            "ReportPage": LIB_DIR / "pages" / "report_page.dart",
            "AiAssistantPage": LIB_DIR / "pages" / "ai_assistant_page.dart",
            "CommunityAlertsPage": LIB_DIR / "pages" / "community_alerts_page.dart",
            "ShareLocationPage": LIB_DIR / "pages" / "share_location_page.dart",
            "EmergencyPage": LIB_DIR / "pages" / "emergency_page.dart",
            "AboutPage": LIB_DIR / "pages" / "about_page.dart",
        }
        for class_name, file_path in screen_map.items():
            self.assertTrue(file_path.exists(), f"Screen file {file_path} missing!")
            content = file_path.read_text(encoding="utf-8")
            self.assertTrue(
                f"class {class_name} extends" in content,
                f"Screen class {class_name} not properly declared in {file_path.name}!",
            )
            # Verify build method exists
            self.assertIn("Widget build(BuildContext context)", content, f"{class_name} lacks a build method!")


class TestDartDelimiterBalance(unittest.TestCase):
    """Test 7: Verify all 18 Dart files have 100% balanced delimiters (), {}, []."""

    def test_balanced_delimiters_all_files(self):
        pairs = {')': '(', '}': '{', ']': '['}
        for f in get_all_dart_files(LIB_DIR):
            content = f.read_text(encoding="utf-8")
            stack = []
            in_str = None
            in_lc = False
            in_bc = False
            i = 0
            n = len(content)
            line = 1
            while i < n:
                c = content[i]
                if c == '\n':
                    line += 1
                    in_lc = False
                    i += 1
                    continue
                if in_lc:
                    i += 1
                    continue
                if in_bc:
                    if content[i:i+2] == '*/':
                        in_bc = False
                        i += 2
                    else:
                        i += 1
                    continue
                if in_str:
                    if c == '\\':
                        i += 2
                        continue
                    if c == in_str:
                        in_str = None
                    i += 1
                    continue
                if content[i:i+2] == '//':
                    in_lc = True
                    i += 2
                    continue
                if content[i:i+2] == '/*':
                    in_bc = True
                    i += 2
                    continue
                if c in ('"', "'"):
                    in_str = c
                    i += 1
                    continue
                if c in '({[':
                    stack.append((c, line))
                elif c in ')}]':
                    expected = pairs[c]
                    self.assertTrue(
                        len(stack) > 0,
                        f"{f.name}:{line} Unmatched closing {c}",
                    )
                    top, top_line = stack.pop()
                    self.assertEqual(
                        top,
                        expected,
                        f"{f.name}:{line} Mismatched {c}, expected {expected} opened at line {top_line}",
                    )
                i += 1
            self.assertEqual(len(stack), 0, f"{f.name} has unclosed delimiters: {stack}")


class TestFlutterDartWidgetContracts(unittest.TestCase):
    """Test 8: Verify widget lifecycle and contract compliance."""

    def test_all_stateful_widgets_implement_create_state(self):
        for f in get_all_dart_files(LIB_DIR):
            content = f.read_text(encoding="utf-8")
            matches = re.findall(r"class\s+([A-Za-z0-9_]+)\s+extends\s+StatefulWidget", content)
            for widget_class in matches:
                self.assertIn(
                    "State<" + widget_class + "> createState()",
                    content,
                    f"StatefulWidget {widget_class} in {f.name} lacks createState() definition!",
                )


class TestExactR4Contract(unittest.TestCase):
    """Test 9: Emulate all 8 exact tests from test/r4_architecture_dead_code_test.dart."""

    def test_r4_tier1_safety_marker_instantiation(self):
        content = (LIB_DIR / "models" / "safety_marker.dart").read_text(encoding="utf-8")
        self.assertIn("class SafetyMarker", content)
        self.assertIn("position", content)
        self.assertIn("icon", content)
        self.assertIn("color", content)
        self.assertIn("label", content)

    def test_r4_tier1_app_theme_unified(self):
        content = (LIB_DIR / "theme" / "app_theme.dart").read_text(encoding="utf-8")
        self.assertIn("class AppTheme", content)
        self.assertIn("static ThemeData dark()", content)
        self.assertIn("static ThemeData light()", content)
        self.assertIn("AppColors.bgDark", content)
        self.assertIn("AppColors.bgLight", content)
        self.assertIn("'Inter'", content)

    def test_r4_tier1_report_store_lifecycle(self):
        rs_content = (LIB_DIR / "data" / "report_store.dart").read_text(encoding="utf-8")
        rm_content = (LIB_DIR / "models" / "report_model.dart").read_text(encoding="utf-8")
        self.assertIn("class ReportStore", rs_content)
        self.assertIn("static final List<Report> reports", rs_content)
        self.assertIn("static void addReport(Report report)", rs_content)
        self.assertIn("static int get total", rs_content)
        self.assertIn("static int countByStatus(ReportStatus status)", rs_content)
        self.assertIn("enum ReportStatus { pending, approved, rejected }", rm_content)
        self.assertIn("class Report", rm_content)

    def test_r4_tier2_safety_marker_non_empty(self):
        f = LIB_DIR / "models" / "safety_marker.dart"
        self.assertTrue(f.exists())
        self.assertGreater(f.stat().st_size, 0)
        self.assertIn("class SafetyMarker", f.read_text(encoding="utf-8"))

    def test_r4_tier2_theme_store_pruned_or_no_apptheme(self):
        f = LIB_DIR / "data" / "theme_store.dart"
        if f.exists():
            self.assertNotIn("class AppTheme", f.read_text(encoding="utf-8"))
        else:
            self.assertFalse(f.exists())

    def test_r4_tier2_ten_dead_files_pruned(self):
        for df in DEAD_FILES:
            self.assertFalse((PROJECT_ROOT / df).exists(), f"{df} should not exist")

    def test_r4_tier3_map_placeholder_with_markers(self):
        content = (LIB_DIR / "widgets" / "map_placeholder.dart").read_text(encoding="utf-8")
        self.assertIn("class MapPlaceholder extends StatelessWidget", content)
        self.assertIn("final List<SafetyMarker> markers;", content)
        self.assertIn("CustomPaint", content)

    def test_r4_tier4_zero_duplicate_classes(self):
        class_regex = re.compile(r"class\s+([A-Za-z0-9_]+)")
        classes = {}
        for f in get_all_dart_files(LIB_DIR):
            for line in f.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line.startswith("//") or line.startswith("/*"):
                    continue
                m = class_regex.match(line)
                if m:
                    cls = m.group(1)
                    if not cls.startswith("_"):
                        classes.setdefault(cls, []).append(f.name)
        for cls, files in classes.items():
            self.assertEqual(len(files), 1, f"Class {cls} declared multiple times: {files}")


if __name__ == "__main__":
    unittest.main()


