# ==============================================================================
# SafeSphere Quality Automation & Continuous Verification (/automation)
# Runs backend tests, mobile contracts, PRD compliance, and security tests
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [SafeSphere Automation] Running Automated Verification" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot -or (Test-Path "$PSScriptRoot\backend")) {
    $ProjectRoot = $PSScriptRoot
}

$ErrorCount = 0

# 1. Backend Integration Tests
Write-Host "`n[Stage 1] Executing Backend API Integration Tests..." -ForegroundColor Yellow
python -m unittest "$ProjectRoot\backend\tests\test_api.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] Backend API tests failed!" -ForegroundColor Red
    $ErrorCount++
} else {
    Write-Host "  [PASS] Backend API tests passed cleanly." -ForegroundColor Green
}

# 2. Adversarial Routing & Navigation Tests
Write-Host "`n[Stage 2] Executing Adversarial Navigation & Route Tests..." -ForegroundColor Yellow
python "$ProjectRoot\test\adversarial_r1_challenger_test.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] Adversarial navigation tests failed!" -ForegroundColor Red
    $ErrorCount++
} else {
    Write-Host "  [PASS] Adversarial navigation tests passed." -ForegroundColor Green
}

# 3. Challenger Test Suites
Write-Host "`n[Stage 3] Executing Milestone Challenger Suites..." -ForegroundColor Yellow
$challengers = @(
    "test\challenger_m2_empirical_test.py",
    "test\challenger_m3_empirical_test.py",
    "test\challenger_m4_2_empirical_test.py",
    "test\test_r5_permissions_contrast.py"
)

foreach ($ch in $challengers) {
    python "$ProjectRoot\$ch"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Challenger test: $ch failed!" -ForegroundColor Red
        $ErrorCount++
    } else {
        Write-Host "  [PASS] $ch passed." -ForegroundColor Green
    }
}

# 4. Monorepo Architecture & Contracts Health Check
Write-Host "`n[Stage 4] System Architecture & OpenAPI Contracts Check..." -ForegroundColor Yellow
python "$ProjectRoot\automation\health_check.py"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] System health check failed!" -ForegroundColor Red
    $ErrorCount++
} else {
    Write-Host "  [PASS] System health check passed." -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($ErrorCount -eq 0) {
    Write-Host " [SafeSphere Automation] ALL AUTOMATION STAGES PASSED (100%)" -ForegroundColor Green
    exit 0
} else {
    Write-Host " [SafeSphere Automation] FAILED WITH $ErrorCount ERRORS" -ForegroundColor Red
    exit 1
}
Write-Host "==========================================================" -ForegroundColor Cyan
