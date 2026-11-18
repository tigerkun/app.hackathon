#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " [SafeSphere Automation] Running Automated Verification"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "\n[Stage 1] Executing Backend API Integration Tests..."
npm --prefix "$PROJECT_ROOT/backend" test

echo -e "\n[Stage 2] Executing Adversarial Navigation & Route Tests..."
python3 "$PROJECT_ROOT/frontend/test/adversarial_r1_challenger_test.py" || python "$PROJECT_ROOT/frontend/test/adversarial_r1_challenger_test.py"

echo -e "\n[Stage 3] Executing Milestone Challenger Suites..."
python3 "$PROJECT_ROOT/frontend/test/challenger_m2_empirical_test.py" || python "$PROJECT_ROOT/frontend/test/challenger_m2_empirical_test.py"
python3 "$PROJECT_ROOT/frontend/test/challenger_m3_empirical_test.py" || python "$PROJECT_ROOT/frontend/test/challenger_m3_empirical_test.py"
python3 "$PROJECT_ROOT/frontend/test/challenger_m4_2_empirical_test.py" || python "$PROJECT_ROOT/frontend/test/challenger_m4_2_empirical_test.py"
python3 "$PROJECT_ROOT/frontend/test/test_r5_permissions_contrast.py" || python "$PROJECT_ROOT/frontend/test/test_r5_permissions_contrast.py"

echo -e "\n[Stage 4] System Architecture & OpenAPI Contracts Check..."
python3 "$PROJECT_ROOT/automation/health_check.py" || python "$PROJECT_ROOT/automation/health_check.py"

echo "=========================================================="
echo " [SafeSphere Automation] ALL AUTOMATION STAGES PASSED (100%)"
echo "=========================================================="
