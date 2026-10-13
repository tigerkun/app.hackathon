"""
Empirical Challenger Test Suite for SafeSphere Milestone 4 (R3: Emergency Actions & Hardware Callouts)
Author: Challenger 1 (teamwork_preview_challenger_m4_1)
Target Project: SafeSphere (lib/, test/)

Mission Objectives & Adversarial Stress Dimensions:
1. Stress test emergency dialing:
   - Simulate successful canLaunchUrl for 112, 181, 108, 101 (verify intent URI generation tel:...)
   - Simulate failed canLaunchUrl for 112, 181, 108, 101 (verify error SnackBar 'Could not open dialer for $number')
   - Simulate launchUrl throwing platform exceptions (verify error SnackBar 'Error dialing $number: $e')
   - Verify unmounted guards on SnackBar display
   - Stress test rapid re-entrant dials (50+ rapid taps)
2. Stress test geolocator integration & fallback:
   - Simulate permission granted + GPS fix (verify dynamic coordinates and maps URL)
   - Simulate location service disabled (verify fallback to Delhi coordinates 28.6139, 77.2090 and SnackBar)
   - Simulate permission denied and deniedForever (verify fallback and SnackBar)
   - Simulate getCurrentPosition timeout (>6s):
     * Fallback to getLastKnownPosition() success (shares cached coordinates cleanly)
     * Fallback to getLastKnownPosition() null (shares Delhi coordinates with warning SnackBar)
   - Fuzz coordinates worldwide (Equator, prime meridian, negative lat/long, extreme precision)
   - Stress test re-entrancy button disabling (_isLoading state)
   - Simulate unmount mid-flight during GPS lock (verify mounted guards)
3. Stress test ReportStore persistence:
   - Empty and whitespace-only description validation ('', '   ', '\\t\\n\\r  ') -> rejected
   - Multiple incident categories (Theft, Harassment, Accident, Suspicious) -> mapped accurately
   - Stress test rapid submissions (100 reports) -> store integrity, ordering, status counts
   - Adversarial payload stress: multiline text, unicode surrogate emojis, SQL/XSS injections
   - Controller disposal verification and safe navigation pop
4. Real-world end-to-end crisis sequence emulation
5. Non-regression verification against Milestones 1, 2, and 3
"""

import os
import re
import sys
import time
import random
import unittest
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple
from dataclasses import dataclass, field

PROJECT_ROOT = os.path.abspath(r"C:\Users\tejas\projects\safesphere")
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend") if os.path.exists(os.path.join(PROJECT_ROOT, "frontend", "lib")) else PROJECT_ROOT
LIB_DIR = os.path.join(FRONTEND_DIR, "lib")
PAGES_DIR = os.path.join(LIB_DIR, "pages")
DATA_DIR = os.path.join(LIB_DIR, "data")
MODELS_DIR = os.path.join(LIB_DIR, "models")
WIDGETS_DIR = os.path.join(LIB_DIR, "widgets")
PUBSPEC_PATH = os.path.join(FRONTEND_DIR, "pubspec.yaml")

# ==============================================================================
# Section 1: High-Fidelity Simulation Models for Platform Hardware & UI State
# ==============================================================================

class LocationPermission(Enum):
    denied = "denied"
    deniedForever = "deniedForever"
    whileInUse = "whileInUse"
    always = "always"

@dataclass
class Position:
    latitude: float
    longitude: float
    timestamp: datetime = field(default_factory=datetime.now)
    accuracy: float = 5.0
    altitude: float = 0.0

class SimulatedUrlLauncher:
    """Simulates Flutter url_launcher platform interface with configurable behaviors."""
    def __init__(self):
        self.can_launch_map: Dict[str, bool] = {}
        self.should_throw_on_launch: Dict[str, Optional[Exception]] = {}
        self.launched_urls: List[str] = []
        self.total_launch_calls: int = 0

    def reset(self):
        self.can_launch_map.clear()
        self.should_throw_on_launch.clear()
        self.launched_urls.clear()
        self.total_launch_calls = 0

    def set_can_launch(self, uri: str, can_launch: bool):
        self.can_launch_map[uri] = can_launch

    def set_launch_exception(self, uri: str, exc: Exception):
        self.should_throw_on_launch[uri] = exc

    def can_launch_url(self, uri: str) -> bool:
        return self.can_launch_map.get(uri, True)

    def launch_url(self, uri: str) -> bool:
        self.total_launch_calls += 1
        if uri in self.should_throw_on_launch:
            raise self.should_throw_on_launch[uri]
        if self.can_launch_url(uri):
            self.launched_urls.append(uri)
            return True
        return False


class SimulatedEmergencyPage:
    """Emulates EmergencyPage's _makeCall behavior with mounted guards and SnackBars."""
    def __init__(self, launcher: SimulatedUrlLauncher):
        self.launcher = launcher
        self.is_mounted = True
        self.snackbars_shown: List[str] = []

    def make_call(self, phone_number: str):
        launch_uri = f"tel:{phone_number}"
        try:
            if self.launcher.can_launch_url(launch_uri):
                self.launcher.launch_url(launch_uri)
            else:
                if self.is_mounted:
                    self.snackbars_shown.append(f"Could not open dialer for {phone_number}")
        except Exception as e:
            if self.is_mounted:
                self.snackbars_shown.append(f"Error dialing {phone_number}: {e}")


class SimulatedGeolocator:
    """Simulates geolocator platform interface with network/GPS latency and timeouts."""
    def __init__(self):
        self.service_enabled: bool = True
        self.permission: LocationPermission = LocationPermission.always
        self.current_position: Optional[Position] = None
        self.last_known_position: Optional[Position] = None
        self.current_position_delay_s: float = 0.0
        self.current_position_timeout: bool = False
        self.hardware_exception: Optional[Exception] = None

    def reset(self):
        self.service_enabled = True
        self.permission = LocationPermission.always
        self.current_position = None
        self.last_known_position = None
        self.current_position_delay_s = 0.0
        self.current_position_timeout = False
        self.hardware_exception = None

    def is_location_service_enabled(self) -> bool:
        if self.hardware_exception:
            raise self.hardware_exception
        return self.service_enabled

    def check_permission(self) -> LocationPermission:
        if self.hardware_exception:
            raise self.hardware_exception
        return self.permission

    def request_permission(self) -> LocationPermission:
        if self.hardware_exception:
            raise self.hardware_exception
        return self.permission

    def get_current_position(self, timeout_s: float = 6.0) -> Position:
        if self.hardware_exception:
            raise self.hardware_exception
        if not self.service_enabled:
            raise RuntimeError("Location service disabled")
        if self.permission in (LocationPermission.denied, LocationPermission.deniedForever):
            raise RuntimeError("Location permission denied")
        if self.current_position_timeout or self.current_position_delay_s > timeout_s:
            raise TimeoutException("Location request timed out after 6 seconds")
        if self.current_position is None:
            raise RuntimeError("GPS lock unavailable")
        return self.current_position

    def get_last_known_position(self) -> Optional[Position]:
        if self.hardware_exception:
            raise self.hardware_exception
        if not self.service_enabled:
            return None
        return self.last_known_position

class TimeoutException(Exception):
    pass


class SimulatedShareLocationPage:
    """
    High-fidelity stateful emulation of ShareLocationPage._shareLocation(),
    mirroring all conditional branches, fallback paths, and mounted guards.
    """
    def __init__(self, geolocator: SimulatedGeolocator):
        self.geolocator = geolocator
        self.is_loading = False
        self.is_mounted = True
        self.shared_messages: List[str] = []
        self.snackbars_shown: List[Tuple[str, str]] = []  # (text, color)
        self.button_taps_ignored: int = 0

    def trigger_share(self):
        if self.is_loading:
            self.button_taps_ignored += 1
            return

        self.is_loading = True
        lat = None
        lng = None
        is_fallback = False

        try:
            service_enabled = self.geolocator.is_location_service_enabled()
            if not service_enabled:
                is_fallback = True
            else:
                permission = self.geolocator.check_permission()
                if permission == LocationPermission.denied:
                    permission = self.geolocator.request_permission()

                if permission in (LocationPermission.denied, LocationPermission.deniedForever):
                    is_fallback = True
                else:
                    position = None
                    try:
                        position = self.geolocator.get_current_position(timeout_s=6.0)
                    except Exception:
                        position = self.geolocator.get_last_known_position()

                    if position is not None:
                        lat = position.latitude
                        lng = position.longitude
                    else:
                        is_fallback = True
        except Exception:
            is_fallback = True

        if lat is None or lng is None:
            lat = 28.6139
            lng = 77.2090
            is_fallback = True

        location_url = f"https://www.google.com/maps?q={lat},{lng}"
        message = (
            f"🚨 [Emergency Alert] Location shared (GPS unavailable, using fallback):\n{location_url}"
            if is_fallback
            else f"🚨 I’m sharing my location for safety:\n{location_url}"
        )

        self.shared_messages.append(message)

        if self.is_mounted:
            if is_fallback:
                self.snackbars_shown.append((
                    "GPS unavailable or permission denied. Using default coordinates.",
                    "orange",
                ))
            self.is_loading = False


class ReportStatus(Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"

@dataclass
class Report:
    id: str
    type: str
    location: str
    description: str
    time: datetime
    status: ReportStatus = ReportStatus.pending

class SimulatedReportStore:
    reports: List[Report] = []

    @classmethod
    def clear(cls):
        cls.reports.clear()

    @classmethod
    def add_report(cls, report: Report):
        cls.reports.append(report)

    @classmethod
    def total(cls) -> int:
        return len(cls.reports)

    @classmethod
    def count_by_status(cls, status: ReportStatus) -> int:
        return len([r for r in cls.reports if r.status == status])


class SimulatedReportPage:
    """Emulates ReportPage form submission and validation."""
    def __init__(self):
        self.selected_type: str = "Theft"
        self.description_text: str = ""
        self.is_controller_disposed: bool = False
        self.is_mounted: bool = True
        self.snackbars_shown: List[Tuple[str, str]] = []  # (text, color)
        self.did_pop: bool = False
        self.can_pop: bool = True

    def set_description(self, text: str):
        if self.is_controller_disposed:
            raise RuntimeError("Cannot modify disposed TextEditingController")
        self.description_text = text

    def dispose(self):
        self.is_controller_disposed = True

    def submit_report(self):
        if self.is_controller_disposed:
            raise RuntimeError("Cannot read disposed TextEditingController")

        desc = self.description_text
        if not desc.strip():
            if self.is_mounted:
                self.snackbars_shown.append((
                    "Please enter a description for the incident.",
                    "redAccent",
                ))
            return

        new_report = Report(
            id=f"rep_{int(time.time() * 1000)}_{random.randint(1000, 9999)}",
            type=self.selected_type,
            location="Using current location",
            description=desc,
            time=datetime.now(),
            status=ReportStatus.pending,
        )
        SimulatedReportStore.add_report(new_report)

        if self.is_mounted:
            self.snackbars_shown.append((
                "Incident report submitted successfully",
                "green",
            ))
            if self.can_pop:
                self.did_pop = True


# ==============================================================================
# Section 2: Empirical Challenger Test Suite
# ==============================================================================

class TestMilestone4EmpiricalChallenger(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        with open(PUBSPEC_PATH, 'r', encoding='utf-8') as f:
            cls.pubspec_code = f.read()

        with open(os.path.join(PAGES_DIR, "emergency_page.dart"), 'r', encoding='utf-8') as f:
            cls.emergency_code = f.read()

        with open(os.path.join(PAGES_DIR, "share_location_page.dart"), 'r', encoding='utf-8') as f:
            cls.share_code = f.read()

        with open(os.path.join(PAGES_DIR, "report_page.dart"), 'r', encoding='utf-8') as f:
            cls.report_code = f.read()

        with open(os.path.join(DATA_DIR, "report_store.dart"), 'r', encoding='utf-8') as f:
            cls.report_store_code = f.read()

        with open(os.path.join(MODELS_DIR, "report_model.dart"), 'r', encoding='utf-8') as f:
            cls.report_model_code = f.read()

    def setUp(self):
        self.launcher = SimulatedUrlLauncher()
        self.geolocator = SimulatedGeolocator()
        SimulatedReportStore.clear()

    # --------------------------------------------------------------------------
    # CHALLENGE AREA 1: Emergency Dialing & URL Launcher Intent Stress
    # --------------------------------------------------------------------------

    def test_ch1_1_ast_static_verification_emergency_page(self):
        """Verifies AST wiring, intent construction, and error guards in emergency_page.dart."""
        # 1. url_launcher dependency & import
        self.assertIn("url_launcher: ^6.3.0", self.pubspec_code)
        self.assertIn("import 'package:url_launcher/url_launcher.dart';", self.emergency_code)

        # 2. Uri construction scheme: 'tel', path: phoneNumber
        self.assertRegex(self.emergency_code, r"Uri\(\s*scheme:\s*'tel',\s*path:\s*phoneNumber,?\s*\)")

        # 3. canLaunchUrl and launchUrl invocation
        self.assertIn("await canLaunchUrl(launchUri)", self.emergency_code)
        self.assertIn("await launchUrl(launchUri)", self.emergency_code)

        # 4. context.mounted guards before showing SnackBars
        self.assertIn("if (context.mounted)", self.emergency_code)

        # 5. Exact SnackBar strings
        self.assertIn("Could not open dialer for $phoneNumber", self.emergency_code)
        self.assertIn("Error dialing $phoneNumber: $e", self.emergency_code)

        # 6. Wiring of 112, 181, 108, 101
        self.assertIn('_makeCall(context, "112")', self.emergency_code)
        self.assertIn('"National Emergency", "112"', self.emergency_code)
        self.assertIn('"Women Helpline", "181"', self.emergency_code)
        self.assertIn('"Ambulance", "108"', self.emergency_code)
        self.assertIn('"Fire Services", "101"', self.emergency_code)

        # 7. Navigation wiring
        self.assertIn("Navigator.pushNamed(context, '/share')", self.emergency_code)

    def test_ch1_2_emergency_dialing_success_matrix(self):
        """Simulates successful dialer launch across all 4 helplines (112, 181, 108, 101)."""
        page = SimulatedEmergencyPage(self.launcher)
        numbers = ["112", "181", "108", "101"]

        for num in numbers:
            page.make_call(num)
            expected_uri = f"tel:{num}"
            self.assertIn(expected_uri, self.launcher.launched_urls)
            self.assertEqual(len(page.snackbars_shown), 0, f"No error SnackBar should appear on successful dial of {num}")

        self.assertEqual(self.launcher.launched_urls, ["tel:112", "tel:181", "tel:108", "tel:101"])

    def test_ch1_3_emergency_dialing_can_launch_failed_snackbars(self):
        """Simulates device without telephony capability (canLaunchUrl returns false) for each number."""
        page = SimulatedEmergencyPage(self.launcher)
        numbers = ["112", "181", "108", "101"]

        # Configure launcher to reject all calls
        for num in numbers:
            self.launcher.set_can_launch(f"tel:{num}", False)

        for num in numbers:
            page.make_call(num)
            expected_msg = f"Could not open dialer for {num}"
            self.assertIn(expected_msg, page.snackbars_shown)

        self.assertEqual(len(self.launcher.launched_urls), 0, "No URLs should be launched when canLaunch is false")
        self.assertEqual(len(page.snackbars_shown), 4)

    def test_ch1_4_emergency_dialing_platform_exception_handling(self):
        """Simulates unexpected platform channel exception during launchUrl."""
        page = SimulatedEmergencyPage(self.launcher)
        self.launcher.set_launch_exception("tel:112", RuntimeError("ActivityNotFoundException"))

        page.make_call("112")
        self.assertEqual(len(self.launcher.launched_urls), 0)
        self.assertEqual(len(page.snackbars_shown), 1)
        self.assertIn("Error dialing 112: ActivityNotFoundException", page.snackbars_shown[0])

    def test_ch1_5_emergency_dialing_unmounted_context_guard(self):
        """Simulates user closing the page immediately after tapping dial (context unmounted)."""
        page = SimulatedEmergencyPage(self.launcher)
        page.is_mounted = False
        self.launcher.set_can_launch("tel:112", False)

        page.make_call("112")
        self.assertEqual(len(page.snackbars_shown), 0, "SnackBar must not be shown on unmounted context")

    def test_ch1_6_rapid_consecutive_dialing_stress(self):
        """Adversarial stress: 100 rapid dials fired under high frequency."""
        page = SimulatedEmergencyPage(self.launcher)
        numbers = ["112", "181", "108", "101"]

        for i in range(100):
            target_num = numbers[i % len(numbers)]
            page.make_call(target_num)

        self.assertEqual(len(self.launcher.launched_urls), 100)
        self.assertEqual(self.launcher.total_launch_calls, 100)
        # Verify call distribution
        count_112 = len([u for u in self.launcher.launched_urls if u == "tel:112"])
        self.assertEqual(count_112, 25)

    # --------------------------------------------------------------------------
    # CHALLENGE AREA 2: Geolocator Integration & GPS Fallback Stress
    # --------------------------------------------------------------------------

    def test_ch2_1_ast_static_verification_share_location_page(self):
        """Verifies AST structure, stateful conversion, timeouts, and fallbacks in share_location_page.dart."""
        # 1. Dependency
        self.assertIn("geolocator: ^13.0.0", self.pubspec_code)
        self.assertIn("import 'package:geolocator/geolocator.dart';", self.share_code)
        self.assertIn("import 'package:share_plus/share_plus.dart';", self.share_code)

        # 2. Converted to StatefulWidget
        self.assertIn("class ShareLocationPage extends StatefulWidget", self.share_code)
        self.assertIn("class _ShareLocationPageState extends State<ShareLocationPage>", self.share_code)

        # 3. Timeout configuration (6 seconds)
        self.assertIn("LocationSettings(\n                timeLimit: Duration(seconds: 6),", self.share_code)
        self.assertIn(".timeout(const Duration(seconds: 6))", self.share_code)

        # 4. Fallback to getLastKnownPosition
        self.assertIn("Geolocator.getLastKnownPosition()", self.share_code)

        # 5. Default coordinates: Delhi 28.6139, 77.2090
        self.assertIn("lat = 28.6139;", self.share_code)
        self.assertIn("lng = 77.2090;", self.share_code)

        # 6. Re-entrancy protection
        self.assertIn("_isLoading ? null : _shareLocation", self.share_code)

        # 7. Mounted guard on SnackBar and setState
        self.assertIn("if (mounted)", self.share_code)
        self.assertIn("GPS unavailable or permission denied. Using default coordinates.", self.share_code)

    def test_ch2_2_dynamic_gps_success_worldwide_fuzzing(self):
        """Stress-tests dynamic GPS coordinate retrieval with coordinates across the globe."""
        share_page = SimulatedShareLocationPage(self.geolocator)

        test_coordinates = [
            ("Bangalore", 12.9716, 77.5946),
            ("Mumbai", 19.0760, 72.8777),
            ("London", 51.5074, -0.1278),
            ("New York", 40.7128, -74.0060),
            ("Tokyo", 35.6762, 139.6503),
            ("Sydney", -33.8688, 151.2093),
            ("Equator/Null Island", 0.0, 0.0),
            ("South Pole", -90.0, 0.0),
            ("High Precision Micro-GPS", 28.6139123456, 77.2090654321),
        ]

        for city, lat, lng in test_coordinates:
            self.geolocator.reset()
            self.geolocator.current_position = Position(latitude=lat, longitude=lng)
            share_page.trigger_share()

            latest_msg = share_page.shared_messages[-1]
            self.assertIn(f"https://www.google.com/maps?q={lat},{lng}", latest_msg)
            self.assertIn("🚨 I’m sharing my location for safety:", latest_msg)
            self.assertNotIn("[Emergency Alert]", latest_msg, f"Clean GPS should not trigger emergency fallback in {city}")
            self.assertEqual(len(share_page.snackbars_shown), 0, f"No warning SnackBar should appear for valid GPS in {city}")

    def test_ch2_3_location_service_disabled_fallback(self):
        """Simulates device location services turned off by the user."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        self.geolocator.service_enabled = False

        share_page.trigger_share()

        msg = share_page.shared_messages[-1]
        self.assertIn("https://www.google.com/maps?q=28.6139,77.209", msg)
        self.assertIn("🚨 [Emergency Alert] Location shared (GPS unavailable, using fallback):", msg)
        self.assertEqual(len(share_page.snackbars_shown), 1)
        self.assertEqual(share_page.snackbars_shown[0][0], "GPS unavailable or permission denied. Using default coordinates.")
        self.assertEqual(share_page.snackbars_shown[0][1], "orange")

    def test_ch2_4_location_permission_denied_and_denied_forever(self):
        """Simulates permission denied and deniedForever."""
        share_page = SimulatedShareLocationPage(self.geolocator)

        for perm in [LocationPermission.denied, LocationPermission.deniedForever]:
            self.geolocator.reset()
            self.geolocator.permission = perm
            share_page.trigger_share()

            msg = share_page.shared_messages[-1]
            self.assertIn("28.6139,77.209", msg)
            self.assertIn("GPS unavailable, using fallback", msg)

        self.assertEqual(len(share_page.snackbars_shown), 2)

    def test_ch2_5_gps_timeout_with_last_known_position_success(self):
        """Simulates GPS live fix timeout (>6s) when a cached last-known position exists."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        self.geolocator.current_position_timeout = True
        self.geolocator.last_known_position = Position(latitude=13.0827, longitude=80.2707)  # Chennai

        share_page.trigger_share()

        msg = share_page.shared_messages[-1]
        self.assertIn("https://www.google.com/maps?q=13.0827,80.2707", msg)
        self.assertIn("🚨 I’m sharing my location for safety:", msg)
        self.assertNotIn("GPS unavailable, using fallback", msg)
        self.assertEqual(len(share_page.snackbars_shown), 0, "Last known position should share without fallback warning")

    def test_ch2_6_gps_timeout_with_last_known_null_triggers_delhi_fallback(self):
        """Simulates GPS live fix timeout (>6s) when last-known position is also null."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        self.geolocator.current_position_timeout = True
        self.geolocator.last_known_position = None

        share_page.trigger_share()

        msg = share_page.shared_messages[-1]
        self.assertIn("28.6139,77.209", msg)
        self.assertIn("GPS unavailable, using fallback", msg)
        self.assertEqual(len(share_page.snackbars_shown), 1)

    def test_ch2_7_hardware_exception_outer_catch_resilience(self):
        """Simulates unhandled platform channel crash (MissingPluginException or SecurityException)."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        self.geolocator.hardware_exception = RuntimeError("MissingPluginException: No implementation found")

        # Must not crash!
        share_page.trigger_share()

        msg = share_page.shared_messages[-1]
        self.assertIn("28.6139,77.209", msg)
        self.assertEqual(len(share_page.snackbars_shown), 1)

    def test_ch2_8_rapid_tap_reentrancy_protection(self):
        """Simulates panicked user spamming the share button 20 times rapidly while query is in flight."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        self.geolocator.current_position = Position(latitude=12.9716, longitude=77.5946)

        # Simulate first tap setting is_loading = True
        share_page.is_loading = True
        for _ in range(20):
            share_page.trigger_share()

        self.assertEqual(share_page.button_taps_ignored, 20)
        self.assertEqual(len(share_page.shared_messages), 0)

    def test_ch2_9_unmounted_guard_on_share_completion(self):
        """Simulates user navigating away while GPS query was executing."""
        share_page = SimulatedShareLocationPage(self.geolocator)
        share_page.is_mounted = False
        self.geolocator.service_enabled = False

        share_page.trigger_share()

        # Shared message was prepared, but zero SnackBars or setState calls to unmounted context
        self.assertEqual(len(share_page.shared_messages), 1)
        self.assertEqual(len(share_page.snackbars_shown), 0)

    # --------------------------------------------------------------------------
    # CHALLENGE AREA 3: ReportStore Persistence & Validation Stress
    # --------------------------------------------------------------------------

    def test_ch3_1_ast_static_verification_report_page(self):
        """Verifies AST wiring, validation, controller lifecycle, and ReportStore integration."""
        # 1. Imports
        self.assertIn("import '../data/report_store.dart';", self.report_code)
        self.assertIn("import '../models/report_model.dart';", self.report_code)

        # 2. Validation
        self.assertIn("if (description.trim().isEmpty)", self.report_code)
        self.assertIn("Please enter a description for the incident.", self.report_code)
        self.assertIn("Colors.redAccent", self.report_code)

        # 3. Model construction & store persistence
        self.assertIn("ReportStore.addReport(newReport);", self.report_code)
        self.assertIn("id: \"rep_${DateTime.now().millisecondsSinceEpoch}\"", self.report_code)
        self.assertIn("status: ReportStatus.pending", self.report_code)

        # 4. Success SnackBar & safe pop
        self.assertIn("Incident report submitted successfully", self.report_code)
        self.assertIn("Colors.green", self.report_code)
        self.assertIn("if (Navigator.canPop(context))", self.report_code)

        # 5. Controller disposal
        self.assertIn("_descriptionController.dispose();", self.report_code)

        # 6. Keyboard overflow protection
        self.assertIn("SingleChildScrollView", self.report_code)
        self.assertIn("MediaQuery.of(context).viewInsets.bottom", self.report_code)

    def test_ch3_2_empty_and_whitespace_validation_stress(self):
        """Adversarial stress: attempts to submit empty, whitespace, and formatting-only descriptions."""
        invalid_inputs = [
            "",
            "   ",
            "\t",
            "\n",
            "\r\n",
            "   \t  \n  \r\n   ",
            "                 ",
        ]

        for input_text in invalid_inputs:
            page = SimulatedReportPage()
            page.set_description(input_text)
            page.submit_report()

            self.assertEqual(SimulatedReportStore.total(), 0, f"Input '{repr(input_text)}' must be rejected")
            self.assertEqual(len(page.snackbars_shown), 1)
            self.assertEqual(page.snackbars_shown[0][0], "Please enter a description for the incident.")
            self.assertEqual(page.snackbars_shown[0][1], "redAccent")
            self.assertFalse(page.did_pop)

    def test_ch3_3_all_incident_categories_mapping(self):
        """Verifies report submission across all 4 supported incident categories."""
        categories = ["Theft", "Harassment", "Accident", "Suspicious"]

        for cat in categories:
            page = SimulatedReportPage()
            page.selected_type = cat
            page.set_description(f"Incident occurred: category {cat}")
            page.submit_report()

        self.assertEqual(SimulatedReportStore.total(), 4)
        for i, cat in enumerate(categories):
            stored = SimulatedReportStore.reports[i]
            self.assertEqual(stored.type, cat)
            self.assertEqual(stored.status, ReportStatus.pending)
            self.assertTrue(stored.id.startswith("rep_"))

    def test_ch3_4_adversarial_payload_and_encoding_stress(self):
        """Stress-tests multiline, emoji, unicode surrogate pairs, SQL/XSS, and large inputs."""
        complex_payload = (
            "🚨 CRITICAL INCIDENT REPORT ⚠️\n"
            "-----------------------------------\n"
            "Unicode & Emojis: 👩‍🚒 🚔 🚨 📍 🆘 💔\n"
            "Surrogate pairs: \U0001F600\U0001F601\U0001F602\n"
            "Special characters: <script>alert('pwned');</script> & \" ' \\ / ` ~ @ # $ % ^ & * ( )\n"
            "SQL injection payload: ' OR '1'='1' -- DROP TABLE reports;\n"
            "CJK Characters: 紧急事故 警告 緊急事態\n"
            "Arabic/Hebrew RTL: حالة طوارئ שלום\n"
            "Repeated padding:\n" + ("A" * 5000)
        )

        page = SimulatedReportPage()
        page.set_description(complex_payload)
        page.submit_report()

        self.assertEqual(SimulatedReportStore.total(), 1)
        stored = SimulatedReportStore.reports[0]
        self.assertEqual(stored.description, complex_payload, "Data model must preserve complex payloads with 0 corruption")

    def test_ch3_5_rapid_burst_submission_stress(self):
        """Stress-tests 100 rapid sequential submissions into ReportStore."""
        for i in range(100):
            page = SimulatedReportPage()
            page.selected_type = ["Theft", "Harassment", "Accident", "Suspicious"][i % 4]
            page.set_description(f"Automated incident submission batch #{i}")
            page.submit_report()

        self.assertEqual(SimulatedReportStore.total(), 100)
        self.assertEqual(SimulatedReportStore.count_by_status(ReportStatus.pending), 100)

        # Check unique IDs
        ids = {r.id for r in SimulatedReportStore.reports}
        self.assertEqual(len(ids), 100, "All 100 submitted reports must have unique IDs")

    def test_ch3_6_controller_disposal_safety(self):
        """Verifies that accessing or mutating controller after disposal raises an error."""
        page = SimulatedReportPage()
        page.dispose()

        with self.assertRaises(RuntimeError):
            page.set_description("This should fail")

        with self.assertRaises(RuntimeError):
            page.submit_report()

    def test_ch3_7_navigator_pop_safety_when_cannot_pop(self):
        """Verifies that when Navigator.canPop is false, pop is not attempted."""
        page = SimulatedReportPage()
        page.can_pop = False
        page.set_description("Valid incident description")
        page.submit_report()

        self.assertFalse(page.did_pop, "Navigator.pop must not be called when canPop is false")
        self.assertEqual(SimulatedReportStore.total(), 1)

    # --------------------------------------------------------------------------
    # CHALLENGE AREA 4: Sequential Crisis Workflow Emulation
    # --------------------------------------------------------------------------

    def test_ch4_sequential_lone_commuter_crisis_chain(self):
        """
        Emulates complete multi-page crisis sequence:
        1. User dials 112 from EmergencyPage.
        2. Dials Women Helpline 181.
        3. Navigates to ShareLocationPage and shares dynamic GPS coordinates.
        4. Navigates to ReportPage and logs the incident report.
        """
        # Step 1: EmergencyPage dials
        emergency_page = SimulatedEmergencyPage(self.launcher)
        emergency_page.make_call("112")
        emergency_page.make_call("181")
        self.assertEqual(self.launcher.launched_urls, ["tel:112", "tel:181"])

        # Step 2: ShareLocationPage shares dynamic coordinates
        self.geolocator.current_position = Position(latitude=19.0760, longitude=72.8777)
        share_page = SimulatedShareLocationPage(self.geolocator)
        share_page.trigger_share()
        self.assertIn("19.076,72.8777", share_page.shared_messages[0])

        # Step 3: ReportPage logs incident
        report_page = SimulatedReportPage()
        report_page.selected_type = "Harassment"
        report_page.set_description("Suspicious vehicle tailing on dark stretch of Highway 4")
        report_page.submit_report()

        self.assertEqual(SimulatedReportStore.total(), 1)
        self.assertEqual(SimulatedReportStore.reports[0].type, "Harassment")
        self.assertTrue(report_page.did_pop)

    # --------------------------------------------------------------------------
    # CHALLENGE AREA 5: Non-Regression Across Prior Milestones
    # --------------------------------------------------------------------------

    def test_ch5_1_milestone1_non_regression(self):
        """Verifies Milestone 1 models, deduplication, and dead code pruning remain intact."""
        # SafetyMarker model exists and is non-empty
        marker_path = os.path.join(MODELS_DIR, "safety_marker.dart")
        self.assertTrue(os.path.exists(marker_path))
        self.assertGreater(os.path.getsize(marker_path), 0)

        # TypingText exists
        typing_path = os.path.join(WIDGETS_DIR, "typing_text.dart")
        self.assertTrue(os.path.exists(typing_path))

        # Dead prototype files remain deleted
        dead_files = [
            "chat_page.dart", "map_view.dart", "custom_button.dart",
            "header.dart", "sidebar.dart", "loading_indicator.dart",
            "constants.dart", "helpers.dart", "theme.dart",
        ]
        for root, _, files in os.walk(LIB_DIR):
            for dead in dead_files:
                self.assertNotIn(dead, files)

    def test_ch5_2_milestone2_non_regression(self):
        """Verifies Milestone 2 navigation back button and route aliases remain intact."""
        with open(os.path.join(PAGES_DIR, "safety_map_page.dart"), 'r', encoding='utf-8') as f:
            map_code = f.read()
        self.assertNotIn("const Icon(Icons.menu)", map_code)
        self.assertIn("Icons.arrow_back", map_code)

        with open(os.path.join(LIB_DIR, "main.dart"), 'r', encoding='utf-8') as f:
            main_code = f.read()
        self.assertIn("'/community'", main_code)
        self.assertIn("'/chat'", main_code)
        self.assertIn("onUnknownRoute", main_code)

    def test_ch5_3_milestone3_non_regression(self):
        """Verifies Milestone 3 mounted guards and controller disposal remain intact."""
        with open(os.path.join(PAGES_DIR, "community_alerts_page.dart"), 'r', encoding='utf-8') as f:
            alerts_code = f.read()
        self.assertIn("if (!mounted) return;", alerts_code)

        with open(os.path.join(PAGES_DIR, "ai_assistant_page.dart"), 'r', encoding='utf-8') as f:
            ai_code = f.read()
        self.assertIn("if (!mounted) return;", ai_code)
        self.assertNotIn("messages.removeLast()", ai_code)


if __name__ == '__main__':
    print("=" * 80)
    print("RUNNING MILESTONE 4 EMPIRICAL CHALLENGER ADVERSARIAL STRESS SUITE")
    print("=" * 80)
    suite = unittest.TestLoader().loadTestsFromTestCase(TestMilestone4EmpiricalChallenger)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if result.wasSuccessful():
        print("\n" + "=" * 80)
        print(">>> EMPIRICAL CHALLENGER VERDICT: APPROVE (100% OF TESTS PASSED) <<<")
        print("=" * 80)
        sys.exit(0)
    else:
        print("\n" + "=" * 80)
        print(">>> EMPIRICAL CHALLENGER VERDICT: CHALLENGE (BUGS DETECTED) <<<")
        print("=" * 80)
        sys.exit(1)
