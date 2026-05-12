/**
 * Claude-Internal Figma Bridge Server
 *
 * 在 localhost:9528 运行，通过 Python PTY helper 管理 claude-internal，
 * 将终端 I/O 转发给 Figma 插件。
 *
 * 用法: node bridge.js
 */

const http = require('http');
const { spawn } = require('child_process');
const crypto = require('crypto');
const os = require('os');
const path = require('path');

// ─── 配置 ────────────────────────────────────────────
const PORT = 9528;
const CLI_COMMAND = 'claude-internal';
const AUTH_TOKEN = crypto.randomBytes(16).toString('hex');

// ─── 输出缓冲 ───────────────────────────────────────
let chunks = [];
let totalOffset = 0;

// ─── Process ─────────────────────────────────────────
let proc = null;
let alive = false;
let cols = 80;
let rows = 24;

function spawnCLI() {
  const helperPath = path.join(__dirname, 'pty-helper.py');

  proc = spawn('python3', [helperPath], {
    env: {
      ...process.env,
      BRIDGE_CLI: CLI_COMMAND,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      COLUMNS: String(cols),
      LINES: String(rows),
    },
    cwd: os.homedir(),
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  alive = true;
  console.log(`[bridge] ${CLI_COMMAND} started (pid ${proc.pid})`);

  proc.stdout.on('data', (data) => {
    const str = data.toString();
    chunks.push({ data: str, offset: totalOffset });
    totalOffset += str.length;
    if (chunks.length > 3000) chunks = chunks.slice(-1500);
  });

  proc.stderr.on('data', (data) => {
    process.stderr.write(data);
  });

  proc.on('exit', (code) => {
    console.log(`[bridge] Process exited (code ${code}). Will restart on next connect.`);
    alive = false;
  });

  proc.on('error', (err) => {
    console.error(`[bridge] Error: ${err.message}`);
    alive = false;
  });
}

// ─── HTTP ────────────────────────────────────────────
function body(req) {
  return new Promise((resolve) => {
    let d = '';
    req.on('data', (c) => d += c);
    req.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve({}); } });
  });
}

function json(res, obj, code = 200) {
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  });
  res.end(JSON.stringify(obj));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    });
    return res.end();
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const p = url.pathname;

  if (p === '/health') {
    if (!alive) {
      chunks = [];
      totalOffset = 0;
      spawnCLI();
    }
    return json(res, { status: 'ok', token: AUTH_TOKEN, message: alive ? 'running' : 'starting' });
  }

  if (p === '/output') {
    const since = parseInt(url.searchParams.get('since') || '0', 10);
    const out = [];
    for (const c of chunks) { if (c.offset >= since) out.push(c.data); }
    return json(res, { chunks: out, nextOffset: totalOffset });
  }

  if (p === '/input') {
    const b = await body(req);
    if (b.data && proc && alive && proc.stdin.writable) {
      proc.stdin.write(b.data);
    }
    return json(res, { ok: true });
  }

  if (p === '/resize') {
    const b = await body(req);
    cols = b.cols || 80;
    rows = b.rows || 24;
    if (proc && alive && proc.stdin.writable) {
      proc.stdin.write(`\x1b]resize;${rows};${cols}\x07`);
    }
    return json(res, { ok: true });
  }

  if (p === '/disconnect') {
    return json(res, { ok: true });
  }

  json(res, { error: 'not found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[bridge] Claude-Internal Figma Bridge running on http://localhost:${PORT}`);
  console.log(`[bridge] Open Figma plugin to connect.\n`);
  spawnCLI();
});

process.on('SIGINT', () => { if (proc) proc.kill(); process.exit(0); });
process.on('SIGTERM', () => { if (proc) proc.kill(); process.exit(0); });
