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
  if npm install -g @tencent/claude-code-internal; then
    echo "   ✅ claude-internal 已安装"
  else
    echo "   ⚠️  claude-internal 自动安装失败，可能是未配置公司内部 npm registry"
    echo "      将继续安装插件文件；请稍后手动安装 claude-internal 后再启动 bridge"
  fi
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
  "main": "bridge.js",
  "scripts": {
    "start": "node bridge.js"
  },
  "dependencies": {
    "xterm": "^5.3.0",
    "@xterm/addon-fit": "^0.10.0"
  }
}
PKGJSON

# ─── 写入运行时文件 ────────────────────────────────────
cp "$REPO_DIR/bridge.js" "$INSTALL_DIR/bridge.js"
cp "$REPO_DIR/pty-helper.py" "$INSTALL_DIR/pty-helper.py"
cp "$REPO_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/uninstall.sh"

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
