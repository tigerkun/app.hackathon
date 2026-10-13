#!/usr/bin/env node
/**
 * SafeSphere Monorepo - Development Environment Runner
 * Concurrently spawns the backend service and frontend web preview server
 * with cross-platform support and graceful shutdown handling.
 */

const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const rootDir = path.resolve(__dirname, '..');
const nodeCmd = process.execPath;
const isWindows = process.platform === 'win32';

console.log('================================================================');
console.log('  SafeSphere Enterprise Monorepo - Development Environment');
console.log('================================================================');

const processes = [];

// 1. Launch Backend API Service
const backendPkgPath = path.join(rootDir, 'backend', 'package.json');
const backendServerPath = path.join(rootDir, 'backend', 'src', 'server.js');

if (fs.existsSync(backendServerPath)) {
  console.log('[Dev] Starting Backend Node.js/Express API (Port 3000)...');
  const backendProcess = spawn(nodeCmd, [backendServerPath], {
    cwd: path.join(rootDir, 'backend'),
    stdio: 'inherit',
    env: { ...process.env, PORT: process.env.PORT || '3000' }
  });
  processes.push(backendProcess);
} else if (fs.existsSync(backendPkgPath)) {
  console.log('[Dev] Starting Backend Service via npm start...');
  const npmCmd = isWindows ? 'npm.cmd' : 'npm';
  const backendProcess = spawn(npmCmd, ['--prefix', 'backend', 'start'], {
    cwd: rootDir,
    stdio: 'inherit',
    shell: true
  });
  processes.push(backendProcess);
} else {
  console.log('[Dev] Backend Node.js service pending Milestone 2 implementation.');
}

// 2. Launch Frontend Web Preview Server
const previewServerPath = path.join(rootDir, 'frontend', 'web_preview', 'server.js');
if (fs.existsSync(previewServerPath)) {
  console.log('[Dev] Starting Frontend Web Preview (Port 8080)...');
  const previewProcess = spawn(nodeCmd, [previewServerPath], {
    cwd: path.join(rootDir, 'frontend', 'web_preview'),
    stdio: 'inherit'
  });
  processes.push(previewProcess);
} else {
  console.warn('[Dev] Warning: Frontend web preview server not found at: ' + previewServerPath);
}

let isShuttingDown = false;
function handleShutdown() {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log('\n[Dev] Gracefully shutting down SafeSphere services...');
  for (const proc of processes) {
    try {
      if (proc.pid) {
        if (isWindows) {
          try {
            execSync(`taskkill /pid ${proc.pid} /T /F`, { stdio: 'ignore' });
          } catch (e) {
            proc.kill();
          }
        } else {
          proc.kill('SIGTERM');
        }
      }
    } catch (err) {}
  }
  process.exit(0);
}

process.on('SIGINT', handleShutdown);
process.on('SIGTERM', handleShutdown);
process.on('exit', () => {
  if (!isShuttingDown) handleShutdown();
});
