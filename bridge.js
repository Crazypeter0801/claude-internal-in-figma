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
const PORT = Number.parseInt(process.env.BRIDGE_PORT || '9528', 10) || 9528;
const CLI_COMMAND = process.env.BRIDGE_CLI || 'claude-internal';
const AUTH_TOKEN = crypto.randomBytes(16).toString('hex');
const MAX_BODY_BYTES = 1024 * 1024;

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
  return new Promise((resolve, reject) => {
    let d = '';
    let size = 0;
    let tooLarge = false;
    req.on('data', (c) => {
      if (tooLarge) return;
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        tooLarge = true;
        reject(new Error('request body too large'));
        return;
      }
      d += c;
    });
    req.on('end', () => {
      if (tooLarge) return;
      try { resolve(JSON.parse(d)); } catch { resolve({}); }
    });
    req.on('error', reject);
  });
}

function isAllowedOrigin(origin) {
  if (!origin) return true;
  if (origin === 'null') return true;
  try {
    const { protocol, hostname } = new URL(origin);
    if (protocol === 'https:' && (hostname === 'figma.com' || hostname.endsWith('.figma.com'))) {
      return true;
    }
    if (protocol === 'http:' && (hostname === 'localhost' || hostname === '127.0.0.1')) {
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

function corsHeaders(req) {
  const origin = req.headers.origin;
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Headers': 'Content-Type, X-Client-Id, X-Auth-Token',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Vary': 'Origin',
  };
  if (origin && isAllowedOrigin(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

function json(req, res, obj, code = 200) {
  res.writeHead(code, corsHeaders(req));
  res.end(JSON.stringify(obj));
}

function isAuthorized(req) {
  const token = req.headers['x-auth-token'];
  if (typeof token !== 'string') return false;
  const expected = Buffer.from(AUTH_TOKEN);
  const actual = Buffer.from(token);
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

function requireAuth(req, res) {
  if (isAuthorized(req)) return true;
  json(req, res, { error: 'unauthorized' }, 401);
  return false;
}

const server = http.createServer(async (req, res) => {
  if (!isAllowedOrigin(req.headers.origin)) {
    res.writeHead(403, { 'Content-Type': 'application/json', 'Vary': 'Origin' });
    return res.end(JSON.stringify({ error: 'origin not allowed' }));
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders(req));
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
    return json(req, res, { status: 'ok', token: AUTH_TOKEN, message: alive ? 'running' : 'starting' });
  }

  if (p === '/output') {
    if (!requireAuth(req, res)) return;
    const since = parseInt(url.searchParams.get('since') || '0', 10);
    const out = [];
    for (const c of chunks) { if (c.offset >= since) out.push(c.data); }
    return json(req, res, { chunks: out, nextOffset: totalOffset });
  }

  if (p === '/input') {
    if (!requireAuth(req, res)) return;
    let b;
    try {
      b = await body(req);
    } catch (err) {
      return json(req, res, { error: err.message }, 413);
    }
    if (b.data && proc && alive && proc.stdin.writable) {
      proc.stdin.write(b.data);
    }
    return json(req, res, { ok: true });
  }

  if (p === '/resize') {
    if (!requireAuth(req, res)) return;
    let b;
    try {
      b = await body(req);
    } catch (err) {
      return json(req, res, { error: err.message }, 413);
    }
    cols = b.cols || 80;
    rows = b.rows || 24;
    if (proc && alive && proc.stdin.writable) {
      proc.stdin.write(`\x1b]resize;${rows};${cols}\x07`);
    }
    return json(req, res, { ok: true });
  }

  if (p === '/disconnect') {
    if (!requireAuth(req, res)) return;
    return json(req, res, { ok: true });
  }

  json(req, res, { error: 'not found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[bridge] Claude-Internal Figma Bridge running on http://localhost:${PORT}`);
  console.log(`[bridge] Open Figma plugin to connect.\n`);
  spawnCLI();
});

process.on('SIGINT', () => { if (proc) proc.kill(); process.exit(0); });
process.on('SIGTERM', () => { if (proc) proc.kill(); process.exit(0); });
