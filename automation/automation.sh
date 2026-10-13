#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " [SafeSphere Automation] Running Automated Verification"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "\n[Stage 1] Executing Backend API Integration Tests..."
python3 -m unittest "$PROJECT_ROOT/backend/tests/test_api.py" || python -m unittest "$PROJECT_ROOT/backend/tests/test_api.py"

echo -e "\n[Stage 2] Executing Adversarial Navigation & Route Tests..."
python3 "$PROJECT_ROOT/test/adversarial_r1_challenger_test.py" || python "$PROJECT_ROOT/test/adversarial_r1_challenger_test.py"

echo -e "\n[Stage 3] Executing Milestone Challenger Suites..."
python3 "$PROJECT_ROOT/test/challenger_m2_empirical_test.py" || python "$PROJECT_ROOT/test/challenger_m2_empirical_test.py"
python3 "$PROJECT_ROOT/test/challenger_m3_empirical_test.py" || python "$PROJECT_ROOT/test/challenger_m3_empirical_test.py"
python3 "$PROJECT_ROOT/test/challenger_m4_2_empirical_test.py" || python "$PROJECT_ROOT/test/challenger_m4_2_empirical_test.py"
python3 "$PROJECT_ROOT/test/test_r5_permissions_contrast.py" || python "$PROJECT_ROOT/test/test_r5_permissions_contrast.py"

echo -e "\n[Stage 4] System Architecture & OpenAPI Contracts Check..."
python3 "$PROJECT_ROOT/automation/health_check.py" || python "$PROJECT_ROOT/automation/health_check.py"

echo "=========================================================="
echo " [SafeSphere Automation] ALL AUTOMATION STAGES PASSED (100%)"
echo "=========================================================="
