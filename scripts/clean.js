#!/usr/bin/env node
/**
 * SafeSphere Monorepo - Cross-Platform Clean Utility
 * Safely removes Flutter build artifacts, pub caches, coverage reports,
 * temporary test outputs, and bytecode caches across all workspaces.
 */

const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');

const targets = [
  'frontend/build',
  'frontend/.dart_tool',
  'frontend/.pub-cache',
  'frontend/coverage',
  'backend/coverage',
  'backend/.nyc_output',
  'coverage',
  '.dart_tool',
  'build'
];

console.log('================================================================');
console.log('  SafeSphere Monorepo - Artifact & Cache Cleanup');
console.log('================================================================\n');

let cleanedCount = 0;

for (const target of targets) {
  const fullPath = path.join(rootDir, target);
  if (fs.existsSync(fullPath)) {
    try {
      fs.rmSync(fullPath, { recursive: true, force: true });
      console.log(`  [Cleaned] Directory: ${target}`);
      cleanedCount++;
    } catch (err) {
      console.warn(`  [Warning] Could not remove ${target}: ${err.message}`);
    }
  }
}

// Clean Python bytecode cache directories (__pycache__) and .pyc files
function cleanBytecode(dir) {
  if (!fs.existsSync(dir)) return;
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return;
  }

  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === '__pycache__') {
        try {
          fs.rmSync(full, { recursive: true, force: true });
          console.log(`  [Cleaned] Cache: ${path.relative(rootDir, full)}`);
          cleanedCount++;
        } catch (e) {}
      } else if (entry.name !== '.git' && entry.name !== 'node_modules' && entry.name !== '.agents') {
        cleanBytecode(full);
      }
    } else if (entry.isFile() && (entry.name.endsWith('.pyc') || entry.name.endsWith('.pyo'))) {
      try {
        fs.unlinkSync(full);
        cleanedCount++;
      } catch (e) {}
    }
  }
}

cleanBytecode(rootDir);

console.log(`\nCleanup complete. (${cleanedCount} items cleaned).`);
console.log('================================================================');
