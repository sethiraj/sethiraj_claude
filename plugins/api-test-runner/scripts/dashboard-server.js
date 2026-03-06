#!/usr/bin/env node
/**
 * dashboard-server.js — Real-time API Test Dashboard
 *
 * Serves the dashboard HTML, exposes REST endpoints for history,
 * and pushes live updates via Server-Sent Events when history.json changes.
 *
 * Usage:
 *   node dashboard-server.js [--port 3737] [--no-open]
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const args = process.argv.slice(2);
const PORT = parseInt(args[args.indexOf('--port') + 1] || process.env.DASHBOARD_PORT || '3737', 10);
const NO_OPEN = args.includes('--no-open');

const PLUGIN_ROOT   = path.join(__dirname, '..');
const RESULTS_DIR   = path.join(PLUGIN_ROOT, 'results');
const HISTORY_FILE  = path.join(RESULTS_DIR, 'history.json');
const DASHBOARD_DIR = path.join(PLUGIN_ROOT, 'dashboard');

// ─── Ensure dirs ──────────────────────────────────────────────────────────────
if (!fs.existsSync(RESULTS_DIR)) fs.mkdirSync(RESULTS_DIR, { recursive: true });

// ─── History helpers ──────────────────────────────────────────────────────────
function loadHistory() {
  if (!fs.existsSync(HISTORY_FILE)) return [];
  try {
    return JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf-8'));
  } catch (_) {
    return [];
  }
}

function computeStats(history) {
  const total  = history.length;
  const passed = history.filter(r => r.passed).length;
  const failed = total - passed;
  const recent = history.slice(0, 20);
  const avgDuration = recent.length
    ? Math.round(recent.reduce((s, r) => s + (r.duration || 0), 0) / recent.length)
    : 0;
  return {
    total,
    passed,
    failed,
    avgDuration,
    passRate: total ? ((passed / total) * 100).toFixed(1) : '0.0',
    lastRun: history[0] ? history[0].timestamp : null,
  };
}

function saveResult(result) {
  const history = loadHistory();
  result.id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  result.timestamp = result.timestamp || new Date().toISOString();
  history.unshift(result);
  if (history.length > 500) history.splice(500);
  fs.writeFileSync(HISTORY_FILE, JSON.stringify(history, null, 2));
  return result;
}

// ─── SSE broadcast ────────────────────────────────────────────────────────────
const sseClients = new Set();

function broadcast(payload) {
  const data = `data: ${JSON.stringify(payload)}\n\n`;
  for (const res of sseClients) {
    try {
      res.write(data);
    } catch (_) {
      sseClients.delete(res);
    }
  }
}

// Watch history.json for changes made by api-runner --report (external process)
let fsWatcher = null;
function watchHistory() {
  if (fsWatcher) return;
  const watchTarget = fs.existsSync(HISTORY_FILE) ? HISTORY_FILE : RESULTS_DIR;
  fsWatcher = fs.watch(watchTarget, { persistent: false }, (event) => {
    if (event === 'change' || event === 'rename') {
      // Small delay to let the write finish
      setTimeout(() => {
        const history = loadHistory();
        if (history.length > 0) {
          broadcast({ type: 'result', data: history[0] });
          broadcast({ type: 'stats',  data: computeStats(history) });
        }
        // Re-attach watcher if file was replaced
        if (event === 'rename') {
          if (fsWatcher) { fsWatcher.close(); fsWatcher = null; }
          setTimeout(watchHistory, 200);
        }
      }, 100);
    }
  });
}
watchHistory();

// ─── MIME types ───────────────────────────────────────────────────────────────
const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.css':  'text/css',
  '.json': 'application/json',
  '.png':  'image/png',
  '.ico':  'image/x-icon',
};

// ─── Request router ───────────────────────────────────────────────────────────
function handleRequest(req, res) {
  const url      = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;
  const method   = req.method;

  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // ── SSE stream ──────────────────────────────────────────────────────────────
  if (pathname === '/api/events') {
    res.writeHead(200, {
      'Content-Type':  'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection':    'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.write(': connected\n\n');
    sseClients.add(res);

    // Heartbeat every 25 s to keep proxies from timing out
    const hb = setInterval(() => {
      try { res.write(': heartbeat\n\n'); } catch (_) { clearInterval(hb); }
    }, 25000);

    req.on('close', () => {
      clearInterval(hb);
      sseClients.delete(res);
    });
    return;
  }

  // ── GET /api/results ────────────────────────────────────────────────────────
  if (pathname === '/api/results' && method === 'GET') {
    const history = loadHistory();
    json(res, 200, history);
    return;
  }

  // ── POST /api/results — record a result from external runner ────────────────
  if (pathname === '/api/results' && method === 'POST') {
    readBody(req, (err, body) => {
      if (err) { json(res, 400, { error: err.message }); return; }
      try {
        const result = JSON.parse(body);
        const saved  = saveResult(result);
        broadcast({ type: 'result', data: saved });
        broadcast({ type: 'stats',  data: computeStats(loadHistory()) });
        json(res, 201, saved);
      } catch (e) {
        json(res, 400, { error: e.message });
      }
    });
    return;
  }

  // ── GET /api/stats ──────────────────────────────────────────────────────────
  if (pathname === '/api/stats' && method === 'GET') {
    json(res, 200, computeStats(loadHistory()));
    return;
  }

  // ── DELETE /api/results — clear history ─────────────────────────────────────
  if (pathname === '/api/results' && method === 'DELETE') {
    fs.writeFileSync(HISTORY_FILE, '[]');
    broadcast({ type: 'cleared' });
    json(res, 200, { ok: true });
    return;
  }

  // ── Static files (dashboard/) ───────────────────────────────────────────────
  const safePath = pathname === '/' ? '/index.html' : pathname;
  const filePath = path.join(DASHBOARD_DIR, path.posix.normalize(safePath));

  // Security: prevent path traversal
  if (!filePath.startsWith(DASHBOARD_DIR)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    const ext  = path.extname(filePath);
    const mime = MIME[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime });
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  res.writeHead(404); res.end('Not found');
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function readBody(req, cb) {
  let body = '';
  req.on('data', chunk => { body += chunk; if (body.length > 5e6) req.destroy(); });
  req.on('end', () => cb(null, body));
  req.on('error', cb);
}

// ─── Start ────────────────────────────────────────────────────────────────────
const server = http.createServer(handleRequest);

server.listen(PORT, '127.0.0.1', () => {
  const url = `http://localhost:${PORT}`;
  console.log('');
  console.log('  ┌─────────────────────────────────────────┐');
  console.log('  │  API Test Runner — Dashboard             │');
  console.log(`  │  ${url.padEnd(41)}│`);
  console.log('  │  Press Ctrl+C to stop                   │');
  console.log('  └─────────────────────────────────────────┘');
  console.log('');
  console.log(`  SSE clients connected: 0`);
  console.log(`  History file: ${HISTORY_FILE}`);
  console.log('');

  if (!NO_OPEN) {
    const openCmd =
      process.platform === 'win32'  ? `start ${url}` :
      process.platform === 'darwin' ? `open ${url}`  :
      `xdg-open ${url}`;
    exec(openCmd, (err) => { if (err) console.log(`  Open ${url} in your browser`); });
  }
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`\n  Port ${PORT} is in use. Try: DASHBOARD_PORT=3738 node dashboard-server.js`);
  } else {
    console.error('\n  Server error:', err.message);
  }
  process.exit(1);
});

process.on('SIGINT',  () => { console.log('\n\n  Dashboard stopped.'); process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
