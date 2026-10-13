# SafeSphere Automation & Booster Suite (`/boost` & `/automation`)

This directory contains continuous verification and developer boost automation scripts for SafeSphere.

## 1. Quick Boost (`/boost`)

Spins up the environment, verifies runtimes, checks contracts, and prepares services:
```powershell
# Windows PowerShell
.\boost.ps1
# or
.\automation\boost.ps1
```
```bash
# Linux / macOS
./automation/boost.sh
```

## 2. Complete Automation Pipeline (`/automation`)

Runs the end-to-end multi-tier test pipeline:
- **Stage 1**: Backend API integration test suite (`backend/tests/test_api.py`)
- **Stage 2**: Adversarial route and navigation state-machine tests (`test/adversarial_r1_challenger_test.py`)
- **Stage 3**: Full milestone challenger suites (M2, M3, M4, R5 contrast & permissions)
- **Stage 4**: Monorepo architecture and OpenAPI contracts validation (`automation/health_check.py`)

```powershell
# Windows PowerShell
.\automation.ps1
# or
.\automation\automation.ps1
```
```bash
# Linux / macOS
./automation/automation.sh
```

## 3. Dedicated Health Check Tool

Inspects directory structure, OpenAPI paths, backend unit tests, and Flutter static tests:
```bash
python automation/health_check.py
```
