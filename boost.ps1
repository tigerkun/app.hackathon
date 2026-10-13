# ==============================================================================
# SafeSphere Developer Booster Script (/boost)
# Orchestrates FastAPI backend, verifies contracts, and boots web preview
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [SafeSphere] Launching Developer Boost Environment" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot -or (Test-Path "$PSScriptRoot\backend")) {
    $ProjectRoot = $PSScriptRoot
}

# 1. Environment Verification
Write-Host "`n[1/4] Verifying Developer Runtimes..." -ForegroundColor Yellow
$py = Get-Command python -ErrorAction SilentlyContinue
$node = Get-Command node -ErrorAction SilentlyContinue

if ($py) {
    Write-Host "  [OK] Python: $(python --version)" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Python not found on PATH" -ForegroundColor Red
}

if ($node) {
    Write-Host "  [OK] Node.js: $(node -v)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Node.js not found on PATH" -ForegroundColor Yellow
}

# 2. Shared Contracts Validation
Write-Host "`n[2/4] Validating Monorepo Architecture & Contracts..." -ForegroundColor Yellow
$contractsFile = Join-Path $ProjectRoot "shared\contracts\api_contracts.json"
if (Test-Path $contractsFile) {
    Write-Host "  [OK] OpenAPI Contracts detected: $contractsFile" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Missing contracts file" -ForegroundColor Red
}

# 3. Running Self-Check Suite
Write-Host "`n[3/4] Running Quick System Self-Check..." -ForegroundColor Yellow
python "$ProjectRoot\automation\health_check.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [WARN] Some health checks flagged notices." -ForegroundColor Yellow
} else {
    Write-Host "  [OK] Health Check 100% Passed!" -ForegroundColor Green
}

# 4. Developer Server Endpoints
Write-Host "`n[4/4] Developer Services Ready to Launch:" -ForegroundColor Yellow
Write-Host "  - FastAPI Backend Server:" -ForegroundColor Cyan
Write-Host "      Command: uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload"
Write-Host "      Swagger Docs: http://127.0.0.1:8000/docs"
Write-Host "  - Web Preview Dashboard:" -ForegroundColor Cyan
Write-Host "      Command: node web_preview/server.js"
Write-Host "      App URL: http://127.0.0.1:8080"
Write-Host "  - Flutter Mobile Application:" -ForegroundColor Cyan
Write-Host "      Command: flutter run"

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [SafeSphere Boost] Environment Ready for Development!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
