#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════
#  Claude Internal in Figma - 一键安装脚本
#
#  安装内容:
#    1. claude-internal CLI (@tencent/claude-code-internal)
#    2. Bridge 服务器 (用于连接 Figma 插件和 claude-internal)
#    3. Figma 插件文件 (导入到 Figma 中使用)
#    4. LaunchAgent (开机自启 bridge 服务)
#
#  使用方法:
#    curl -fsSL <your-internal-url>/install.sh | bash
#
# ══════════════════════════════════════════════════════════

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Documents/Claude-Figma-Plugin"
PLUGIN_DIR="$INSTALL_DIR/figma-plugin"
PLIST_NAME="com.claude-figma-bridge.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"
PORT=9528

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  Claude Internal in Figma - Installer   ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# ─── 检查环境 ────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ 仅支持 macOS"
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "❌ 需要安装 Node.js (建议 v18+)"
  echo "   安装: brew install node"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "❌ 需要 python3 (macOS 通常自带)"
  exit 1
fi

# ─── 安装 claude-internal CLI ─────────────────────────
echo "📦 检查 claude-internal CLI..."
if ! command -v claude-internal &>/dev/null; then
  echo "   安装 @tencent/claude-code-internal..."
  npm install -g @tencent/claude-code-internal
  echo "   ✅ claude-internal 已安装"
else
  echo "   ✅ claude-internal 已存在"
fi

# ─── 创建安装目录 ────────────────────────────────────
echo "📁 安装 Bridge 服务器..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$PLUGIN_DIR"

# ─── 写入 package.json ────────────────────────────────
cat > "$INSTALL_DIR/package.json" << 'PKGJSON'
{
  "name": "claude-figma-bridge",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "xterm": "^5.3.0",
    "@xterm/addon-fit": "^0.10.0"
  }
}
PKGJSON

# ─── 写入 bridge.js (从本仓库复制) ────────────────────
# 这里用 heredoc 内联，实际发布时可以从 CDN/Git 下载
cat > "$INSTALL_DIR/bridge.js" << 'BRIDGEJS'
const http = require('http');
const { spawn } = require('child_process');
const crypto = require('crypto');
const os = require('os');
const path = require('path');

const PORT = 9528;
const CLI_COMMAND = 'claude-internal';
const AUTH_TOKEN = crypto.randomBytes(16).toString('hex');

let chunks = [];
let totalOffset = 0;
let proc = null;
let alive = false;
let cols = 80;
let rows = 24;

function spawnCLI() {
  const helperPath = path.join(__dirname, 'pty-helper.py');
  proc = spawn('python3', [helperPath], {
    env: { ...process.env, BRIDGE_CLI: CLI_COMMAND, TERM: 'xterm-256color', COLORTERM: 'truecolor', COLUMNS: String(cols), LINES: String(rows) },
    cwd: os.homedir(),
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  alive = true;
  proc.stdout.on('data', (data) => {
    const str = data.toString();
    chunks.push({ data: str, offset: totalOffset });
    totalOffset += str.length;
    if (chunks.length > 3000) chunks = chunks.slice(-1500);
  });
  proc.stderr.on('data', (data) => process.stderr.write(data));
  proc.on('exit', () => { alive = false; });
  proc.on('error', () => { alive = false; });
}

function body(req) {
  return new Promise((resolve) => {
    let d = '';
    req.on('data', (c) => d += c);
    req.on('end', () => { try { resolve(JSON.parse(d)); } catch { resolve({}); } });
  });
}

function json(res, obj, code = 200) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' }); return res.end(); }
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const p = url.pathname;
  if (p === '/health') { if (!alive) { chunks = []; totalOffset = 0; spawnCLI(); } return json(res, { status: 'ok', token: AUTH_TOKEN }); }
  if (p === '/output') { const since = parseInt(url.searchParams.get('since') || '0', 10); const out = []; for (const c of chunks) { if (c.offset >= since) out.push(c.data); } return json(res, { chunks: out, nextOffset: totalOffset }); }
  if (p === '/input') { const b = await body(req); if (b.data && proc && alive && proc.stdin.writable) proc.stdin.write(b.data); return json(res, { ok: true }); }
  if (p === '/resize') { const b = await body(req); cols = b.cols || 80; rows = b.rows || 24; if (proc && alive && proc.stdin.writable) proc.stdin.write(`\x1b]resize;${rows};${cols}\x07`); return json(res, { ok: true }); }
  if (p === '/disconnect') { return json(res, { ok: true }); }
  json(res, { error: 'not found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => { console.log(`[bridge] Running on http://localhost:${PORT}`); spawnCLI(); });
process.on('SIGINT', () => { if (proc) proc.kill(); process.exit(0); });
process.on('SIGTERM', () => { if (proc) proc.kill(); process.exit(0); });
BRIDGEJS

# ─── 写入 pty-helper.py ───────────────────────────────
cat > "$INSTALL_DIR/pty-helper.py" << 'PTYHELPER'
import os, sys, pty, select, signal, struct, fcntl, termios, errno

COMMAND = os.environ.get('BRIDGE_CLI', 'claude-internal')

def set_winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))

def main():
    cols = int(os.environ.get('COLUMNS', '80'))
    rows = int(os.environ.get('LINES', '24'))
    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, rows, cols)
    pid = os.fork()
    if pid == 0:
        os.close(master_fd); os.setsid()
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
        os.dup2(slave_fd, 0); os.dup2(slave_fd, 1); os.dup2(slave_fd, 2)
        if slave_fd > 2: os.close(slave_fd)
        env = os.environ.copy()
        env['TERM'] = 'xterm-256color'; env['COLORTERM'] = 'truecolor'
        os.execvpe(COMMAND, [COMMAND], env)
    else:
        os.close(slave_fd)
        flags = fcntl.fcntl(sys.stdin.fileno(), fcntl.F_GETFL)
        fcntl.fcntl(sys.stdin.fileno(), fcntl.F_SETFL, flags | os.O_NONBLOCK)
        input_buf = b''
        RESIZE_PREFIX = b'\x1b]resize;'; RESIZE_END = b'\x07'
        signal.signal(signal.SIGCHLD, lambda s, f: None)
        try:
            while True:
                try: rlist, _, _ = select.select([master_fd, sys.stdin.fileno()], [], [], 0.05)
                except: break
                if master_fd in rlist:
                    try:
                        data = os.read(master_fd, 65536)
                        if not data: break
                        sys.stdout.buffer.write(data); sys.stdout.buffer.flush()
                    except OSError as e:
                        if e.errno == errno.EIO: break
                        raise
                if sys.stdin.fileno() in rlist:
                    try:
                        data = os.read(sys.stdin.fileno(), 65536)
                        if not data: break
                        input_buf += data
                        while input_buf:
                            idx = input_buf.find(RESIZE_PREFIX)
                            if idx == -1: os.write(master_fd, input_buf); input_buf = b''; break
                            elif idx > 0: os.write(master_fd, input_buf[:idx]); input_buf = input_buf[idx:]
                            else:
                                end_idx = input_buf.find(RESIZE_END)
                                if end_idx == -1: break
                                payload = input_buf[len(RESIZE_PREFIX):end_idx]
                                input_buf = input_buf[end_idx+1:]
                                try:
                                    parts = payload.split(b';')
                                    set_winsize(master_fd, int(parts[0]), int(parts[1]))
                                    os.killpg(os.getpgid(pid), signal.SIGWINCH)
                                except: pass
                    except OSError as e:
                        if e.errno == errno.EAGAIN: continue
                        break
                try:
                    if os.waitpid(pid, os.WNOHANG)[0] != 0: break
                except ChildProcessError: break
        finally:
            os.close(master_fd)
            try: os.kill(pid, signal.SIGTERM)
            except: pass
            try: os.waitpid(pid, 0)
            except: pass

if __name__ == '__main__': main()
PTYHELPER

# ─── 安装 Node 依赖 ──────────────────────────────────
cd "$INSTALL_DIR"
npm install --production --silent 2>/dev/null
echo "   ✅ Bridge 服务器已安装"

# ─── 构建 Figma 插件 UI ──────────────────────────────
echo "🔨 构建 Figma 插件..."

# manifest.json — copy from repo
cp "$REPO_DIR/figma-plugin/manifest.json" "$PLUGIN_DIR/manifest.json"

# code.js — copy from repo
cp "$REPO_DIR/figma-plugin/code.js" "$PLUGIN_DIR/code.js"

# ui.html — write template then inline xterm.js from node_modules
# Copy the template from the original repo directory
if [ -f "$REPO_DIR/ui-template.html" ]; then
  cp "$REPO_DIR/ui-template.html" "$INSTALL_DIR/ui-template.html"
else
  echo "   ❌ 找不到 ui-template.html，请在仓库目录下运行此脚本"
  exit 1
fi

node -e "
const fs = require('fs');
const p = require('path');
const dir = '$INSTALL_DIR';
const xterm = fs.readFileSync(p.join(dir, 'node_modules/xterm/lib/xterm.js'), 'utf8');
const fit = fs.readFileSync(p.join(dir, 'node_modules/@xterm/addon-fit/lib/addon-fit.js'), 'utf8');
const css = fs.readFileSync(p.join(dir, 'node_modules/xterm/css/xterm.css'), 'utf8');
const tmpl = fs.readFileSync(p.join(dir, 'ui-template.html'), 'utf8');
const out = tmpl
  .replace('/* __XTERM_CSS__ */', css)
  .replace('/* __XTERM_JS__ */', xterm)
  .replace('/* __FIT_ADDON_JS__ */', fit);
fs.writeFileSync(p.join(dir, 'figma-plugin/ui.html'), out);
console.log('   ✅ Figma 插件已构建 (' + (out.length/1024).toFixed(0) + ' KB)');
"

# ─── 设置 LaunchAgent (开机自启) ─────────────────────
echo "🚀 配置自启动服务..."

# 先停掉旧的（如果有）
launchctl unload "$PLIST_PATH" 2>/dev/null || true

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_NAME</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which node)</string>
    <string>$INSTALL_DIR/bridge.js</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$INSTALL_DIR/bridge.log</string>
  <key>StandardErrorPath</key>
  <string>$INSTALL_DIR/bridge.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(echo $PATH)</string>
  </dict>
</dict>
</plist>
PLIST

launchctl load "$PLIST_PATH"
echo "   ✅ Bridge 服务已启动（开机自动运行）"

# ─── 完成 ────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║  ✅ 安装完成！                                       ║"
echo "  ║                                                      ║"
echo "  ║  下一步：在 Figma 中导入插件                          ║"
echo "  ║                                                      ║"
echo "  ║  1. 打开 Figma 桌面版                                ║"
echo "  ║  2. Plugins → Development → Import plugin            ║"
echo "  ║     from manifest...                                 ║"
echo "  ║  3. 选择以下路径:                                     ║"
echo "  ║     $PLUGIN_DIR/manifest.json"
echo "  ║                                                      ║"
echo "  ║  4. 运行: Plugins → Development →                    ║"
echo "  ║     Claude Internal in Figma                         ║"
echo "  ║                                                      ║"
echo "  ║  首次使用会弹出浏览器进行 OA 登录                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  管理命令:"
echo "    查看日志:  tail -f $INSTALL_DIR/bridge.log"
echo "    重启服务:  launchctl kickstart -k gui/\$(id -u)/$PLIST_NAME"
echo "    停止服务:  launchctl unload $PLIST_PATH"
echo "    卸载全部:  bash $INSTALL_DIR/uninstall.sh"
echo ""
