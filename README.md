# Claude Internal in Figma

在 Figma 中直接使用 Claude Code Internal (claude-internal)，无需切换窗口。

## 安装（一键）

```bash
git clone https://github.com/Crazypeter0801/claude-internal-in-figma.git
cd claude-internal-in-figma
bash install.sh
```

安装脚本会自动完成：
1. 安装 `@tencent/claude-code-internal`（如果没有）
2. 安装 Bridge 服务器到 `~/Documents/Claude-Figma-Plugin/`
3. 构建 Figma 插件（内联 xterm.js 终端）
4. 注册 macOS LaunchAgent（开机自启 bridge 服务）

## 在 Figma 中导入插件（仅需一次）

1. 打开 Figma 桌面版
2. Plugins → Development → Import plugin from manifest...
3. 选择路径：`~/Documents/Claude-Figma-Plugin/figma-plugin/manifest.json`
4. 运行: Plugins → Development → Claude Internal in Figma

首次使用会弹出浏览器进行 OA 登录。

> 注意：自动生成选中画板的 Figma 链接依赖 Figma 的 private plugin API。这个插件的
> `manifest.json` 已开启 `enablePrivatePluginApi`，请以 Development/private plugin
> 方式导入使用；如果更新后仍拿不到链接，先重新运行 `bash install.sh`，再在 Figma
> 里移除旧的 development plugin 并重新从 manifest 导入。

## 管理命令

```bash
# 查看 bridge 日志
tail -f ~/Documents/Claude-Figma-Plugin/bridge.log

# 重启 bridge
launchctl kickstart -k gui/$(id -u)/com.claude-figma-bridge.plist

# 停止 bridge
launchctl unload ~/Library/LaunchAgents/com.claude-figma-bridge.plist

# 完全卸载
bash ~/Documents/Claude-Figma-Plugin/uninstall.sh
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
