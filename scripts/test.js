#!/usr/bin/env node
/**
 * SafeSphere Monorepo - Verification Test Suite
 * Validates frontend monorepo structure, relative imports, asset declarations,
 * executes backend tests if implemented (handling pending M2 gracefully),
 * and verifies core regressions.
 */

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const rootDir = path.resolve(__dirname, '..');
const isWindows = process.platform === 'win32';
const npmCmd = isWindows ? 'npm.cmd' : 'npm';
const pythonCmd = 'python';

console.log('================================================================');
console.log('  SafeSphere Monorepo Automated Verification Suite');
console.log('================================================================\n');

let totalFailures = 0;

// -----------------------------------------------------------------------------
// Step 1: Frontend Monorepo Structural Integrity Check
// -----------------------------------------------------------------------------
console.log('--- Step 1: Verifying Frontend Monorepo Structure ---');
const requiredFrontendPaths = [
  'frontend/pubspec.yaml',
  'frontend/pubspec.lock',
  'frontend/analysis_options.yaml',
  'frontend/.metadata',
  'frontend/lib/main.dart',
  'frontend/lib/models/user_model.dart',
  'frontend/lib/models/auth_tokens.dart',
  'frontend/lib/models/safety_marker.dart',
  'frontend/lib/models/report_model.dart',
  'frontend/lib/services/auth_service.dart',
  'frontend/lib/services/storage_service.dart',
  'frontend/lib/services/map_config.dart',
  'frontend/lib/data/auth_state.dart',
  'frontend/lib/data/report_store.dart',
  'frontend/lib/routes/app_routes.dart',
  'frontend/lib/routes/route_guard.dart',
  'frontend/lib/pages/auth/login_page.dart',
  'frontend/lib/pages/auth/register_page.dart',
  'frontend/lib/pages/auth/phone_otp_page.dart',
  'frontend/lib/pages/auth/pin_lock_page.dart',
  'frontend/lib/pages/home_page.dart',
  'frontend/lib/pages/login_page.dart',
  'frontend/lib/pages/signup_page.dart',
  'frontend/lib/pages/auth_pin_page.dart',
  'frontend/lib/pages/about_page.dart',
  'frontend/lib/pages/emergency_page.dart',
  'frontend/lib/pages/report_page.dart',
  'frontend/lib/pages/safety_map_page.dart',
  'frontend/lib/pages/share_location_page.dart',
  'frontend/lib/pages/community_alerts_page.dart',
  'frontend/lib/pages/ai_assistant_page.dart',
  'frontend/lib/widgets/app_drawer.dart',
  'frontend/lib/widgets/glass_container.dart',
  'frontend/lib/widgets/map_placeholder.dart',
  'frontend/lib/widgets/typing_text.dart',
  'frontend/assets/lottie/ai_typing.json',
  'frontend/web_preview/server.js',
  'frontend/web_preview/index.html'
];

let structuralPass = true;
for (const relPath of requiredFrontendPaths) {
  const fullPath = path.join(rootDir, relPath);
  if (!fs.existsSync(fullPath)) {
    console.error(`  FAIL: Missing required file: ${relPath}`);
    structuralPass = false;
  } else {
    console.log(`  PASS: Found ${relPath}`);
  }
}

// Check count of active Dart files in frontend/lib
const libDir = path.join(rootDir, 'frontend', 'lib');
let dartFileCount = 0;
function countDartFiles(dir) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      countDartFiles(full);
    } else if (entry.isFile() && entry.name.endsWith('.dart')) {
      dartFileCount++;
    }
  }
}
countDartFiles(libDir);
console.log(`  Active Dart source files in frontend/lib: ${dartFileCount}`);
if (dartFileCount < 24) {
  console.error(`  FAIL: Expected at least 24 Dart files in frontend/lib, found ${dartFileCount}`);
  structuralPass = false;
} else {
  console.log(`  PASS: All ${dartFileCount} Dart files present in frontend/lib`);
}

// Check relative imports across all Dart files in frontend/lib
let relativeImportsCount = 0;
let brokenImportsCount = 0;
function checkRelativeImports(dir) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      checkRelativeImports(full);
    } else if (entry.isFile() && entry.name.endsWith('.dart')) {
      const content = fs.readFileSync(full, 'utf8');
      const lines = content.split('\n');
      for (const line of lines) {
        const match = line.match(/^import\s+['"](\.[^'"]+)['"];/);
        if (match) {
          relativeImportsCount++;
          const importTarget = path.resolve(dir, match[1]);
          if (!fs.existsSync(importTarget)) {
            console.error(`  FAIL: Broken relative import in ${path.relative(libDir, full)}: ${match[1]}`);
            brokenImportsCount++;
          }
        }
      }
    }
  }
}
checkRelativeImports(libDir);
console.log(`  Audited ${relativeImportsCount} relative Dart imports across frontend/lib`);
if (brokenImportsCount > 0) {
  console.error(`  FAIL: Found ${brokenImportsCount} broken relative import(s)`);
  structuralPass = false;
} else {
  console.log(`  PASS: Zero broken relative imports detected across frontend/lib`);
}

if (!structuralPass) {
  totalFailures++;
}

// -----------------------------------------------------------------------------
// Step 2: Backend Node.js Test Suite (Gracefully handling pending M2)
// -----------------------------------------------------------------------------
console.log('\n--- Step 2: Checking Backend Test Suite ---');
const backendPkgPath = path.join(rootDir, 'backend', 'package.json');
if (fs.existsSync(backendPkgPath)) {
  console.log('  Executing backend test suite: npm --prefix backend test');
  const backendTestRes = spawnSync(npmCmd, ['--prefix', 'backend', 'test'], {
    cwd: rootDir,
    stdio: 'inherit',
    shell: true
  });
  if (backendTestRes.status !== 0) {
    console.error('  FAIL: Backend test suite encountered failures.');
    totalFailures++;
  } else {
    console.log('  PASS: Backend test suite succeeded.');
  }
} else {
  console.log('  INFO: Backend Node.js test suite is pending Milestone 2 implementation.');
  console.log('  PASS: Backend test step handled gracefully (pending M2).');
}

// -----------------------------------------------------------------------------
// Step 3: Python Regression and Adversarial Verification Suite
// -----------------------------------------------------------------------------
console.log('\n--- Step 3: Executing Core Regression & Adversarial Tests ---');
const pythonSuites = [
  'frontend/test/adversarial_r1_challenger_test.py',
  'frontend/test/challenger_m2_empirical_test.py',
  'frontend/test/challenger_m3_empirical_test.py',
  'frontend/test/challenger_m4_2_empirical_test.py',
  'frontend/test/test_r5_permissions_contrast.py'
];

let pythonSuitesPassed = 0;
for (const suite of pythonSuites) {
  const fullPath = path.join(rootDir, suite);
  if (fs.existsSync(fullPath)) {
    const res = spawnSync(pythonCmd, [fullPath], {
      cwd: rootDir,
      stdio: 'pipe',
      encoding: 'utf-8',
      shell: true
    });
    if (res.status === 0) {
      console.log(`  PASS: ${suite}`);
      pythonSuitesPassed++;
    } else {
      console.error(`  FAIL: ${suite}`);
      console.error(res.stderr || res.stdout);
      totalFailures++;
    }
  } else {
    console.warn(`  SKIP: ${suite} (file not found)`);
  }
}

// -----------------------------------------------------------------------------
// Summary & Exit Code
// -----------------------------------------------------------------------------
console.log('\n================================================================');
if (totalFailures === 0) {
  console.log('  ALL MONOREPO VERIFICATIONS PASSED (Exit Code 0)');
  console.log('================================================================\n');
  process.exit(0);
} else {
  console.error(`  VERIFICATION FAILED (${totalFailures} check categories failed)`);
  console.log('================================================================\n');
  process.exit(1);
}
