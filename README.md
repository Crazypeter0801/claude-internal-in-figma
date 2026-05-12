# Claude Internal in Figma

在 Figma 中直接使用 Claude Code Internal (claude-internal)，无需切换窗口。

## 同事安装方式（一键）

```bash
curl -fsSL <your-internal-url>/install.sh | bash
```

或者从内部 Git 仓库：

```bash
git clone <repo-url>
cd claude-figma-bridge
bash install.sh
```

安装脚本会自动完成：
1. 安装 `@tencent/claude-code-internal`（如果没有）
2. 安装 Bridge 服务器到 `~/.claude-figma-bridge/`
3. 构建 Figma 插件（内联 xterm.js 终端）
4. 注册 macOS LaunchAgent（开机自启 bridge 服务）

安装完成后只需在 Figma 中导入插件一次。

## 使用方法

1. 打开 Figma 桌面版
2. Plugins → Development → Import plugin from manifest...
3. 选择 `~/.claude-figma-bridge/figma-plugin/manifest.json`
4. 运行: Plugins → Development → Claude Internal in Figma
5. 首次使用会弹出浏览器进行 OA 登录

之后每次打开 Figma 插件即可直接使用，bridge 服务在后台自动运行。

## 管理命令

```bash
# 查看 bridge 日志
tail -f ~/.claude-figma-bridge/bridge.log

# 重启 bridge
launchctl kickstart -k gui/$(id -u)/com.claude-figma-bridge.plist

# 停止 bridge
launchctl unload ~/Library/LaunchAgents/com.claude-figma-bridge.plist

# 完全卸载
bash ~/.claude-figma-bridge/uninstall.sh
```

## 技术架构

```
Figma 插件 (xterm.js 终端)
    ↕ HTTP localhost:9528
Bridge 服务器 (Node.js)
    ↕ PTY (Python pty 模块)
claude-internal CLI
```

## 系统要求

- macOS
- Figma 桌面版
- Node.js 18+
- Python3 (macOS 自带)
- 内部 npm registry 访问权限（安装 @tencent/claude-code-internal）
