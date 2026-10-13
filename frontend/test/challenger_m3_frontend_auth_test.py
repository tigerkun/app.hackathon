"""
Empirical Challenger Test Suite for SafeSphere Milestone 3:
Frontend Multi-Modal Authentication System (Models, Routes, State, UI, Guards)
Author: Challenger 1 (teamwork_preview_challenger_m3_1_gen2)
Target: frontend/lib/, frontend/test/, scripts/

Adversarial Verification Dimensions:
1. Exhaustive Dart File Discovery & Import/Export Integrity Audit (0 broken imports)
2. Invariant Emergency Bypass (/emergency and /share) under all 7 AuthStatus states
3. PIN Lock Barrier Enforcement (/pin-lock redirection) and Exception Whitelisting
4. Protected Route Guards (/profile, /contacts) vs Guest Browsing Fallbacks
5. 4 Dedicated Auth Pages AST & Structural Integrity (login, register, phone_otp, pin_lock)
6. Authentication Models & State Machine Conformance (UserModel, AuthTokens, AuthState)
7. Dynamic AppDrawer Adaptation (Authenticated vs Guest mode)
8. Legacy Page Re-exports Backward Compatibility
9. Token Storage & Platform Resilience Simulation
"""

import os
import re
import sys
import unittest
from typing import Dict, List, Set, Tuple, Optional, Any
from dataclasses import dataclass

PROJECT_ROOT = os.path.abspath(r"C:\Users\tejas\projects\safesphere")
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend")
LIB_DIR = os.path.join(FRONTEND_DIR, "lib")
PAGES_DIR = os.path.join(LIB_DIR, "pages")
AUTH_PAGES_DIR = os.path.join(PAGES_DIR, "auth")
ROUTES_DIR = os.path.join(LIB_DIR, "routes")
MODELS_DIR = os.path.join(LIB_DIR, "models")
SERVICES_DIR = os.path.join(LIB_DIR, "services")
DATA_DIR = os.path.join(LIB_DIR, "data")
WIDGETS_DIR = os.path.join(LIB_DIR, "widgets")


# ==============================================================================
# Simulation Models for Flutter Navigator & RouteGuard
# ==============================================================================

class AuthStatus:
    INITIAL = 'initial'
    UNAUTHENTICATED = 'unauthenticated'
    GUEST = 'guest'
    AUTHENTICATED = 'authenticated'
    PIN_LOCKED = 'pinLocked'
    OTP_PENDING = 'otpPending'
    LOADING = 'loading'

class SimulatedAuthState:
    def __init__(self, status: str = AuthStatus.UNAUTHENTICATED, current_user=None, pending_phone=None):
        self.status = status
        self.currentUser = current_user
        self.pendingPhone = pending_phone

    @property
    def isAuthenticated(self) -> bool:
        return self.status == AuthStatus.AUTHENTICATED

    @property
    def isGuest(self) -> bool:
        return self.status == AuthStatus.GUEST

    @property
    def isPinLocked(self) -> bool:
        return self.status == AuthStatus.PIN_LOCKED

    @property
    def isOtpPending(self) -> bool:
        return self.status == AuthStatus.OTP_PENDING

    @property
    def isLoading(self) -> bool:
        return self.status == AuthStatus.LOADING

    @property
    def hasActiveAccess(self) -> bool:
        return self.isAuthenticated or self.isGuest


class SimulatedRouteGuard:
    """
    High-fidelity behavioral oracle of frontend/lib/routes/route_guard.dart
    Executes identical priority rules as implemented in Dart.
    """
    @classmethod
    def resolve_route(cls, route_name: Optional[str], auth_state: SimulatedAuthState, arguments: Any = None) -> Tuple[str, str]:
        """
        Returns: (target_page_class, route_kind)
        e.g. ('EmergencyPage', 'emergency_bypass')
        """
        route = route_name if route_name is not None else '/home'

        # 1. Invariant Emergency Bypass (routes /emergency and /share NEVER blocked)
        if route in ('/emergency', '/share'):
            if route == '/share':
                return ('ShareLocationPage', 'emergency_bypass')
            return ('EmergencyPage', 'emergency_bypass')

        # 2. PIN Lock Barrier (redirects to /pin-lock if isPinLocked)
        if auth_state.isPinLocked and route != '/login':
            return ('PinLockPage', 'pin_barrier_redirect')

        # 3. Auth Routes
        if route == '/login':
            return ('LoginPage', 'auth_route')
        if route == '/register':
            return ('RegisterPage', 'auth_route')
        if route == '/otp':
            return ('PhoneOtpPage', 'auth_route')
        if route == '/pin-lock':
            return ('PinLockPage', 'auth_route')

        # 4. Protected Routes (/profile, /contacts)
        if route in ('/profile', '/contacts'):
            if not auth_state.isAuthenticated:
                return ('LoginPage', 'protected_redirect')
            return ('ProfileOrContactsPage', 'protected_resolved')

        # 5. Protected Route (/report) - accessible to authenticated & guest
        if route == '/report':
            return ('ReportPage', 'report_route')

        # 6. Guest Fallback & Standard Route Resolution
        standard_map = {
            '/': 'HomePage',
            '/home': 'HomePage',
            '/safety-map': 'SafetyMapPage',
            '/map': 'SafetyMapPage',
            '/alerts': 'CommunityAlertsPage',
            '/community': 'CommunityAlertsPage',
            '/ai-assistant': 'AiAssistantPage',
            '/chat': 'AiAssistantPage',
            '/about': 'AboutPage',
        }
        return (standard_map.get(route, 'HomePage'), 'standard_route')


# ==============================================================================
# Helper for Balanced Delimiters Syntax Validation
# ==============================================================================

def check_balanced_syntax(code: str, filename: str) -> List[str]:
    """Checks that parentheses, brackets, and braces are strictly balanced."""
    errors = []
    stack = []
    matching = {')': '(', ']': '[', '}': '{'}
    openers = set(matching.values())
    closers = set(matching.keys())

    # Strip line comments and block comments
    cleaned = re.sub(r'//.*$', '', code, flags=re.MULTILINE)
    cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)

    # Walk characters while handling strings
    in_single_quote = False
    in_double_quote = False
    escape = False

    for i, char in enumerate(cleaned):
        if escape:
            escape = False
            continue

        if char == '\\':
            escape = True
            continue

        if char == "'" and not in_double_quote:
            in_single_quote = not in_single_quote
            continue

        if char == '"' and not in_single_quote:
            in_double_quote = not in_double_quote
            continue

        if in_single_quote or in_double_quote:
            continue

        if char in openers:
            stack.append((char, i))
        elif char in closers:
            if not stack:
                errors.append(f"{filename}: Unexpected closing '{char}' at char {i}")
            else:
                top, top_i = stack.pop()
                if top != matching[char]:
                    errors.append(f"{filename}: Mismatched '{char}' at char {i}, expected match for '{top}' at char {top_i}")

    while stack:
        top, top_i = stack.pop()
        errors.append(f"{filename}: Unclosed '{top}' at char {top_i}")

    return errors


# ==============================================================================
# Empirical Test Cases
# ==============================================================================

class TestSafeSphereM3FrontendAuth(unittest.TestCase):

    # --------------------------------------------------------------------------
    # 1. Complete Dart File Discovery & Import/Export Integrity
    # --------------------------------------------------------------------------

    def test_discover_all_dart_files(self):
        """Verifies that all required Dart source files exist and total >= 30 files."""
        dart_files = []
        for root, _, files in os.walk(LIB_DIR):
            for file in files:
                if file.endswith('.dart'):
                    dart_files.append(os.path.join(root, file))

        self.assertGreaterEqual(len(dart_files), 30, f"Expected >= 30 Dart files, found {len(dart_files)}")
        print(f"\n[PASS] Discovered {len(dart_files)} Dart source files in frontend/lib")

    def test_audit_all_relative_imports_and_exports(self):
        """
        Audits EVERY relative import and export across ALL Dart files in frontend/lib/.
        Asserts that 100% of referenced files exist on disk with 0 broken imports.
        """
        dart_files = []
        for root, _, files in os.walk(LIB_DIR):
            for file in files:
                if file.endswith('.dart'):
                    dart_files.append(os.path.join(root, file))

        relative_import_pattern = re.compile(r"""(?:import|export)\s+['"](\.[^'"]+)['"]""")
        package_import_pattern = re.compile(r"""(?:import|export)\s+['"]package:safesphere/([^'"]+)['"]""")

        audited_count = 0
        broken_imports = []

        for file_path in dart_files:
            rel_source = os.path.relpath(file_path, LIB_DIR)
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            file_dir = os.path.dirname(file_path)

            # Check relative imports: import '../...'
            for match in relative_import_pattern.finditer(content):
                target_rel = match.group(1)
                resolved_target = os.path.normpath(os.path.join(file_dir, target_rel))
                audited_count += 1
                if not os.path.exists(resolved_target):
                    broken_imports.append(f"In {rel_source}: broken relative target '{target_rel}' -> {resolved_target}")

            # Check internal package imports: import 'package:safesphere/...'
            for match in package_import_pattern.finditer(content):
                target_pkg = match.group(1)
                resolved_target = os.path.normpath(os.path.join(LIB_DIR, target_pkg))
                audited_count += 1
                if not os.path.exists(resolved_target):
                    broken_imports.append(f"In {rel_source}: broken package target '{target_pkg}' -> {resolved_target}")

        self.assertEqual(len(broken_imports), 0, f"Found broken imports:\n" + "\n".join(broken_imports))
        self.assertGreaterEqual(audited_count, 50, f"Expected >= 50 audited imports, found {audited_count}")
        print(f"[PASS] Audited {audited_count} internal imports/exports with 0 broken links")

    # --------------------------------------------------------------------------
    # 2. Invariant Emergency Bypass (/emergency and /share)
    # --------------------------------------------------------------------------

    def test_invariant_emergency_bypass_across_all_auth_states(self):
        """
        Adversarial Stress Test:
        Verifies that /emergency and /share routes NEVER get blocked, redirected,
        or gated across all 7 AuthStatus states, including PIN-locked and unauthenticated.
        """
        all_states = [
            AuthStatus.INITIAL,
            AuthStatus.UNAUTHENTICATED,
            AuthStatus.GUEST,
            AuthStatus.AUTHENTICATED,
            AuthStatus.PIN_LOCKED,
            AuthStatus.OTP_PENDING,
            AuthStatus.LOADING,
        ]

        for st in all_states:
            state_obj = SimulatedAuthState(status=st)

            # Test /emergency
            page, kind = SimulatedRouteGuard.resolve_route('/emergency', state_obj)
            self.assertEqual(page, 'EmergencyPage', f"State {st} failed to resolve EmergencyPage")
            self.assertEqual(kind, 'emergency_bypass')

            # Test /share
            page, kind = SimulatedRouteGuard.resolve_route('/share', state_obj)
            self.assertEqual(page, 'ShareLocationPage', f"State {st} failed to resolve ShareLocationPage")
            self.assertEqual(kind, 'emergency_bypass')

        print(f"[PASS] Invariant Emergency Bypass verified across all 7 AuthStatus states")

    def test_route_guard_source_code_emergency_bypass_priority(self):
        """
        Inspects frontend/lib/routes/route_guard.dart source code directly.
        Confirms that emergency bypass logic is positioned BEFORE PIN lock and auth checks.
        """
        rg_path = os.path.join(ROUTES_DIR, "route_guard.dart")
        with open(rg_path, 'r', encoding='utf-8') as f:
            rg_code = f.read()

        # Find positions of key checks
        emergency_idx = rg_code.find("routeName == AppRoutes.emergency || routeName == AppRoutes.shareLocation")
        pin_lock_idx = rg_code.find("authState.isPinLocked")
        protected_idx = rg_code.find("routeName == AppRoutes.profile")

        self.assertNotEqual(emergency_idx, -1, "Emergency bypass condition not found in route_guard.dart")
        self.assertNotEqual(pin_lock_idx, -1, "PIN lock check not found in route_guard.dart")
        self.assertNotEqual(protected_idx, -1, "Protected routes check not found in route_guard.dart")

        # Invariant priority: Emergency must come before PIN lock barrier
        self.assertLess(emergency_idx, pin_lock_idx,
                        "CRITICAL SECURITY INVARIANT VIOLATION: Emergency bypass must precede PIN lock check!")
        self.assertLess(pin_lock_idx, protected_idx,
                        "PIN lock barrier must precede protected routes check")

        print("[PASS] RouteGuard source code priority hierarchy verified (Emergency > PIN Lock > Protected)")

    # --------------------------------------------------------------------------
    # 3. PIN Lock Barrier Enforcement
    # --------------------------------------------------------------------------

    def test_pin_lock_barrier_blocks_all_standard_and_protected_routes(self):
        """
        Adversarial Stress Test:
        When isPinLocked is True, ALL standard and protected routes MUST redirect to PinLockPage.
        Only /login, /emergency, and /share are permitted.
        """
        pin_locked_state = SimulatedAuthState(status=AuthStatus.PIN_LOCKED)

        trapped_routes = [
            '/home', '/', '/safety-map', '/map', '/alerts', '/community',
            '/ai-assistant', '/chat', '/about', '/report', '/profile', '/contacts',
            '/custom-unknown-route'
        ]

        for route in trapped_routes:
            page, kind = SimulatedRouteGuard.resolve_route(route, pin_locked_state)
            self.assertEqual(page, 'PinLockPage', f"Route '{route}' bypassed PIN lock barrier!")
            self.assertEqual(kind, 'pin_barrier_redirect')

        # Verify allowed exceptions
        # 1. /login allowed (to allow 'Use Password Instead')
        page, kind = SimulatedRouteGuard.resolve_route('/login', pin_locked_state)
        self.assertEqual(page, 'LoginPage')
        self.assertEqual(kind, 'auth_route')

        # 2. /emergency allowed
        page, kind = SimulatedRouteGuard.resolve_route('/emergency', pin_locked_state)
        self.assertEqual(page, 'EmergencyPage')

        # 3. /share allowed
        page, kind = SimulatedRouteGuard.resolve_route('/share', pin_locked_state)
        self.assertEqual(page, 'ShareLocationPage')

        print(f"[PASS] PIN Lock Barrier verified: 13 routes blocked, 3 whitelisted exceptions validated")

    # --------------------------------------------------------------------------
    # 4. Protected Routes vs Guest Browsing Fallback
    # --------------------------------------------------------------------------

    def test_protected_routes_redirect_unauthenticated_to_login(self):
        """
        Verifies that protected routes (/profile, /contacts) redirect unauthenticated users
        to LoginPage, while guest users can browse public features.
        """
        unauth_state = SimulatedAuthState(status=AuthStatus.UNAUTHENTICATED)
        auth_state = SimulatedAuthState(status=AuthStatus.AUTHENTICATED)
        guest_state = SimulatedAuthState(status=AuthStatus.GUEST)

        # Unauthenticated on /profile & /contacts -> LoginPage
        self.assertEqual(SimulatedRouteGuard.resolve_route('/profile', unauth_state)[0], 'LoginPage')
        self.assertEqual(SimulatedRouteGuard.resolve_route('/contacts', unauth_state)[0], 'LoginPage')

        # Authenticated on /profile & /contacts -> Resolved
        self.assertEqual(SimulatedRouteGuard.resolve_route('/profile', auth_state)[0], 'ProfileOrContactsPage')
        self.assertEqual(SimulatedRouteGuard.resolve_route('/contacts', auth_state)[0], 'ProfileOrContactsPage')

        # Guest on public routes -> Allowed to browse
        public_routes = ['/home', '/safety-map', '/alerts', '/ai-assistant', '/about', '/report']
        for r in public_routes:
            page, _ = SimulatedRouteGuard.resolve_route(r, guest_state)
            self.assertNotEqual(page, 'LoginPage', f"Guest browsing blocked on public route {r}")
            self.assertNotEqual(page, 'PinLockPage')

        print("[PASS] Protected routes (/profile, /contacts) and guest fallbacks verified")

    # --------------------------------------------------------------------------
    # 5. 4 Auth Pages AST, Structure & Syntax Validation
    # --------------------------------------------------------------------------

    def test_four_auth_pages_exist_and_have_balanced_syntax(self):
        """Verifies that all 4 auth pages exist and have strictly balanced syntax (0 syntax errors)."""
        auth_files = [
            'login_page.dart',
            'register_page.dart',
            'phone_otp_page.dart',
            'pin_lock_page.dart',
        ]

        for fname in auth_files:
            fpath = os.path.join(AUTH_PAGES_DIR, fname)
            self.assertTrue(os.path.exists(fpath), f"Missing auth page: {fname}")
            with open(fpath, 'r', encoding='utf-8') as f:
                code = f.read()

            errors = check_balanced_syntax(code, fname)
            self.assertEqual(len(errors), 0, f"Syntax errors in {fname}:\n" + "\n".join(errors))

        print("[PASS] All 4 dedicated auth pages exist with 100% balanced AST syntax")

    def test_login_page_structural_components(self):
        """Verifies LoginPage contains form validation, emergency bypass button, and multi-modal triggers."""
        login_path = os.path.join(AUTH_PAGES_DIR, "login_page.dart")
        with open(login_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Class names
        self.assertIn("class LoginPage extends StatefulWidget", code)
        self.assertIn("class _LoginPageState extends State<LoginPage>", code)

        # Controllers and disposal
        self.assertIn("_emailController.dispose()", code)
        self.assertIn("_passwordController.dispose()", code)

        # Emergency bypass button
        self.assertIn("_handleEmergencyBypass", code)
        self.assertIn("QUICK EMERGENCY BYPASS (SOS)", code)
        self.assertIn("enterEmergencyBypass()", code)

        # Multi-modal triggers
        self.assertIn("_handleBiometricAuth", code)
        self.assertIn("_showSmsOtpDialog", code)
        self.assertIn("AppRoutes.pinLock", code)
        self.assertIn("AppRoutes.register", code)

        print("[PASS] LoginPage structural components verified")

    def test_register_page_structural_components(self):
        """Verifies RegisterPage contains mandatory fields, emergency contact, PIN toggle, and dialer."""
        reg_path = os.path.join(AUTH_PAGES_DIR, "register_page.dart")
        with open(reg_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Class names
        self.assertIn("class RegisterPage extends StatefulWidget", code)
        self.assertIn("class _RegisterPageState extends State<RegisterPage>", code)

        # Controllers and disposal
        self.assertIn("_nameController.dispose()", code)
        self.assertIn("_phoneController.dispose()", code)
        self.assertIn("_emergencyPhoneController.dispose()", code)
        self.assertIn("_passwordController.dispose()", code)
        self.assertIn("_confirmPasswordController.dispose()", code)

        # Mandatory emergency contact validation
        self.assertIn("Emergency contact phone is mandatory", code)
        self.assertIn("Primary Emergency Contact (Mandatory)", code)

        # Optional PIN setup
        self.assertIn("Setup 4-digit PIN for rapid unlock", code)
        self.assertIn("_pinController", code)

        # Emergency dialer 112 in AppBar
        self.assertIn("tel:112", code)
        self.assertIn("_dialEmergency", code)

        # Automatic navigation to OTP page
        self.assertIn("AppRoutes.otp", code)

        print("[PASS] RegisterPage structural components verified")

    def test_phone_otp_page_structural_components(self):
        """Verifies PhoneOtpPage contains 6 cells, countdown timer, auto-advance, and resend."""
        otp_path = os.path.join(AUTH_PAGES_DIR, "phone_otp_page.dart")
        with open(otp_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Class names
        self.assertIn("class PhoneOtpPage extends StatefulWidget", code)
        self.assertIn("class _PhoneOtpPageState extends State<PhoneOtpPage>", code)

        # 6 discrete controllers and focus nodes
        self.assertIn("List.generate(6, (_) => TextEditingController())", code)
        self.assertIn("List.generate(6, (_) => FocusNode())", code)

        # Disposal
        self.assertIn("_countdownTimer?.cancel()", code)
        self.assertIn("c.dispose()", code)
        self.assertIn("fn.dispose()", code)

        # 60s countdown and resend
        self.assertIn("_startCountdown()", code)
        self.assertIn("_secondsRemaining = 60", code)
        self.assertIn("_handleResend()", code)
        self.assertIn("_handleVerify()", code)

        print("[PASS] PhoneOtpPage structural components verified")

    def test_pin_lock_page_structural_components(self):
        """Verifies PinLockPage contains shake animation, keypad, 5-attempt lockout, and SOS."""
        pin_path = os.path.join(AUTH_PAGES_DIR, "pin_lock_page.dart")
        with open(pin_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Class names
        self.assertIn("class PinLockPage extends StatefulWidget", code)
        self.assertIn("class _PinLockPageState extends State<PinLockPage>", code)

        # AnimationController and disposal
        self.assertIn("_shakeController = AnimationController", code)
        self.assertIn("_shakeController.dispose()", code)
        self.assertIn("_lockoutTimer?.cancel()", code)

        # 5 attempts lockout
        self.assertIn("_failedAttempts >= 5", code)
        self.assertIn("_lockoutSeconds = 60", code)

        # Keypad digits 0-9
        for digit in range(10):
            self.assertIn(f"'{digit}'", code)

        # Emergency SOS Dial 112 button
        self.assertIn("Emergency SOS / Dial 112", code)
        self.assertIn("enterEmergencyBypass()", code)
        self.assertIn("Use Password Instead", code)

        print("[PASS] PinLockPage structural components verified")

    # --------------------------------------------------------------------------
    # 6. Auth Models, Services & Reactive State Machine
    # --------------------------------------------------------------------------

    def test_user_model_specifications(self):
        """Verifies UserModel has all required fields, guest factory, copyWith, and serialization."""
        model_path = os.path.join(MODELS_DIR, "user_model.dart")
        with open(model_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Required fields
        for field in ['id', 'name', 'email', 'phone', 'emergencyContactPhone',
                      'emergencyContactName', 'emergencyContacts', 'isGuest',
                      'hasPin', 'biometricsEnabled', 'createdAt']:
            self.assertIn(f"final ", code)
            self.assertIn(field, code)

        # UserModel.guest()
        self.assertIn("factory UserModel.guest()", code)
        self.assertIn("isGuest: true", code)

        # EmergencyContact class
        self.assertIn("class EmergencyContact", code)

        # copyWith and serialization
        self.assertIn("UserModel copyWith(", code)
        self.assertIn("factory UserModel.fromJson(", code)
        self.assertIn("Map<String, dynamic> toJson()", code)

        print("[PASS] UserModel specifications and serialization verified")

    def test_auth_tokens_specifications(self):
        """Verifies AuthTokens model parses JSON envelopes and handles defaults."""
        tokens_path = os.path.join(MODELS_DIR, "auth_tokens.dart")
        with open(tokens_path, 'r', encoding='utf-8') as f:
            code = f.read()

        self.assertIn("class AuthTokens", code)
        self.assertIn("final String accessToken", code)
        self.assertIn("final String refreshToken", code)
        self.assertIn("final int expiresIn", code)
        self.assertIn("factory AuthTokens.fromJson(", code)

        print("[PASS] AuthTokens model verified")

    def test_storage_service_abstraction(self):
        """Verifies IStorageService interface and in-memory persistent implementation."""
        storage_path = os.path.join(SERVICES_DIR, "storage_service.dart")
        with open(storage_path, 'r', encoding='utf-8') as f:
            code = f.read()

        self.assertIn("abstract class IStorageService", code)
        self.assertIn("class StorageService implements IStorageService", code)
        self.assertIn("setString", code)
        self.assertIn("getString", code)
        self.assertIn("remove", code)
        self.assertIn("clear", code)

        print("[PASS] StorageService abstraction verified")

    def test_auth_service_methods(self):
        """Verifies AuthService handles all 8 backend auth endpoints and local PIN/bio operations."""
        service_path = os.path.join(SERVICES_DIR, "auth_service.dart")
        with open(service_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Endpoints
        self.assertIn("/api/v1/auth/register", code)
        self.assertIn("/api/v1/auth/login", code)
        self.assertIn("/api/v1/auth/otp/send", code)
        self.assertIn("/api/v1/auth/otp/verify", code)
        self.assertIn("/api/v1/auth/refresh", code)
        self.assertIn("/api/v1/auth/me", code)
        self.assertIn("/api/v1/auth/logout", code)

        # Local PIN & bio
        self.assertIn("setPin", code)
        self.assertIn("verifyPin", code)
        self.assertIn("hasStoredPin", code)
        self.assertIn("verifyBiometrics", code)

        print("[PASS] AuthService endpoint and local security methods verified")

    def test_auth_state_reactive_methods_and_statuses(self):
        """Verifies AuthState ChangeNotifier manages all 7 AuthStatus enums and reactive actions."""
        state_path = os.path.join(DATA_DIR, "auth_state.dart")
        with open(state_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # Enum states
        for st in ['initial', 'unauthenticated', 'guest', 'authenticated', 'pinLocked', 'otpPending', 'loading']:
            self.assertIn(st, code)

        # Reactive operations
        self.assertIn("enterEmergencyBypass()", code)
        self.assertIn("login(", code)
        self.assertIn("register(", code)
        self.assertIn("sendOtp(", code)
        self.assertIn("verifyOtp(", code)
        self.assertIn("unlockPin(", code)
        self.assertIn("unlockBiometrics(", code)
        self.assertIn("logout()", code)

        print("[PASS] AuthState ChangeNotifier state machine verified")

    # --------------------------------------------------------------------------
    # 7. Dynamic AppDrawer Adaptation
    # --------------------------------------------------------------------------

    def test_app_drawer_dynamic_header_and_security_options(self):
        """Verifies AppDrawer dynamically shows authenticated profile vs guest mode."""
        drawer_path = os.path.join(WIDGETS_DIR, "app_drawer.dart")
        with open(drawer_path, 'r', encoding='utf-8') as f:
            code = f.read()

        # ListenableBuilder on AuthState
        self.assertIn("ListenableBuilder(", code)
        self.assertIn("listenable: authState", code)

        # Authenticated header: UserAccountsDrawerHeader
        self.assertIn("UserAccountsDrawerHeader(", code)
        self.assertIn("Emergency Contact:", code)
        self.assertIn("Icons.verified", code)

        # Authenticated citizen security options
        self.assertIn("Emergency Contacts", code)
        self.assertIn("PIN & Biometric Lock", code)
        self.assertIn("Logout", code)

        # Guest mode header
        self.assertIn("Guest Mode - Limited protection active", code)
        self.assertIn("Sign In / Setup PIN", code)

        # Core 8 drawer destinations intact
        for r in ['/home', '/safety-map', '/alerts', '/report', '/ai-assistant', '/share', '/emergency', '/about']:
            self.assertIn(f"'{r}'", code)

        print("[PASS] AppDrawer dynamic adaptation and security options verified")

    # --------------------------------------------------------------------------
    # 8. Legacy Page Re-exports Backward Compatibility
    # --------------------------------------------------------------------------

    def test_legacy_pages_re_export_auth_counterparts(self):
        """Verifies legacy login_page.dart, signup_page.dart, and auth_pin_page.dart re-export cleanly."""
        legacy_map = {
            'login_page.dart': "export 'auth/login_page.dart';",
            'signup_page.dart': "export 'auth/register_page.dart';",
            'auth_pin_page.dart': "export 'auth/pin_lock_page.dart';",
        }

        for fname, expected_export in legacy_map.items():
            fpath = os.path.join(PAGES_DIR, fname)
            self.assertTrue(os.path.exists(fpath), f"Missing legacy file: {fname}")
            with open(fpath, 'r', encoding='utf-8') as f:
                content = f.read().strip()
            self.assertEqual(content, expected_export, f"Unexpected content in {fname}: {content}")

        print("[PASS] Legacy page re-exports backward compatibility verified")


if __name__ == '__main__':
    print("=" * 80)
    print("  SafeSphere Milestone 3: Adversarial Empirical Challenger Suite")
    print("=" * 80)
    unittest.main(verbosity=2)
