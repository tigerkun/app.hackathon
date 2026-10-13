#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " [SafeSphere] Launching Developer Boost Environment"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "\n[1/4] Verifying Developer Runtimes..."
python3 --version || python --version
node -v || true

echo -e "\n[2/4] Validating Monorepo Architecture & Contracts..."
test -f "$PROJECT_ROOT/shared/contracts/api_contracts.json" && echo "  [OK] OpenAPI Contracts present."

echo -e "\n[3/4] Running Quick System Self-Check..."
python3 "$PROJECT_ROOT/automation/health_check.py" || python "$PROJECT_ROOT/automation/health_check.py"

echo -e "\n[4/4] Developer Services Ready to Launch:"
echo "  - FastAPI Backend Server: uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload"
echo "  - Web Preview Dashboard: node web_preview/server.js"
echo "  - Flutter Mobile Application: flutter run"

echo "=========================================================="
echo " [SafeSphere Boost] Environment Ready for Development!"
echo "=========================================================="
