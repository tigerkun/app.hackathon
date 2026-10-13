#!/usr/bin/env python3
"""
SafeSphere Full-Stack System Health Check
Verifies backend service, shared contracts, and file system integrity.
"""

import sys
import os
import json
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

def check_file_structure():
    print("[1/4] Checking Mono-Repo Directory Architecture...")
    required_paths = [
        PROJECT_ROOT / "backend" / "app" / "main.py",
        PROJECT_ROOT / "backend" / "app" / "api" / "v1" / "auth.py",
        PROJECT_ROOT / "backend" / "app" / "core" / "security.py",
        PROJECT_ROOT / "backend" / "tests" / "test_api.py",
        PROJECT_ROOT / "frontend" / "README.md",
        PROJECT_ROOT / "frontend" / "web_preview" / "index.html",
        PROJECT_ROOT / "shared" / "contracts" / "api_contracts.json",
        PROJECT_ROOT / "shared" / "types" / "auth.ts",
        PROJECT_ROOT / "docs" / "PRD.md",
        PROJECT_ROOT / "docs" / "ARCHITECTURE.md",
        PROJECT_ROOT / "docs" / "API_SPEC.md",
        PROJECT_ROOT / "lib" / "services" / "auth_service.dart",
        PROJECT_ROOT / "lib" / "models" / "user_model.dart",
        PROJECT_ROOT / "lib" / "pages" / "login_page.dart",
        PROJECT_ROOT / "lib" / "pages" / "signup_page.dart",
        PROJECT_ROOT / "lib" / "pages" / "auth_pin_page.dart",
    ]
    all_ok = True
    for p in required_paths:
        if p.exists():
            print(f"  [PASS] Found: {p.relative_to(PROJECT_ROOT)}")
        else:
            print(f"  [FAIL] Missing: {p.relative_to(PROJECT_ROOT)}")
            all_ok = False
    return all_ok

def check_shared_contracts():
    print("\n[2/4] Validating Shared OpenAPI Contracts...")
    contract_file = PROJECT_ROOT / "shared" / "contracts" / "api_contracts.json"
    try:
        with open(contract_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        paths = data.get("paths", {})
        expected_endpoints = ["/auth/signup", "/auth/login", "/auth/login-pin", "/sos/trigger", "/reports", "/markers/nearby"]
        for ep in expected_endpoints:
            if ep in paths:
                print(f"  [PASS] Endpoint mapped: {ep}")
            else:
                print(f"  [FAIL] Missing contract endpoint: {ep}")
                return False
        return True
    except Exception as e:
        print(f"  [FAIL] Contract parsing error: {e}")
        return False

def check_backend_tests():
    print("\n[3/4] Running Backend API Test Harness...")
    import unittest
    from backend.tests.test_api import TestSafeSphereBackendApi

    suite = unittest.TestLoader().loadTestsFromTestCase(TestSafeSphereBackendApi)
    runner = unittest.TextTestRunner(verbosity=1)
    result = runner.run(suite)
    return result.wasSuccessful()

def check_flutter_static_tests():
    print("\n[4/4] Running Core Adversarial & Navigation Test Suites...")
    import subprocess
    scripts = [
        "test/adversarial_r1_challenger_test.py",
        "test/challenger_m2_empirical_test.py",
        "test/challenger_m3_empirical_test.py",
        "test/challenger_m4_2_empirical_test.py",
        "test/test_r5_permissions_contrast.py"
    ]
    all_passed = True
    for script in scripts:
        cmd = [sys.executable, str(PROJECT_ROOT / script)]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            print(f"  [PASS] {script}")
        else:
            print(f"  [FAIL] {script}")
            all_passed = False
    return all_passed

def main():
    print("=" * 60)
    print(" SafeSphere Automated Verification & Health Check Harness")
    print("=" * 60)
    t0 = time.time()
    s1 = check_file_structure()
    s2 = check_shared_contracts()
    s3 = check_backend_tests()
    s4 = check_flutter_static_tests()

    elapsed = round(time.time() - t0, 2)
    print("=" * 60)
    if s1 and s2 and s3 and s4:
        print(f"[SUCCESS] ALL SAFESPHERE HEALTH CHECKS PASSED ({elapsed}s)")
        sys.exit(0)
    else:
        print(f"[FAILURE] SOME CHECKS FAILED ({elapsed}s)")
        sys.exit(1)

if __name__ == "__main__":
    main()
