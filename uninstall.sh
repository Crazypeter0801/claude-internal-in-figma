#!/bin/bash
# 卸载 Claude Internal in Figma

INSTALL_DIR="$HOME/.claude-figma-bridge"
PLIST_PATH="$HOME/Library/LaunchAgents/com.claude-figma-bridge.plist"

echo "卸载 Claude Internal in Figma..."

# 停止服务
launchctl unload "$PLIST_PATH" 2>/dev/null
rm -f "$PLIST_PATH"
echo "  ✅ 服务已停止"

# 删除文件
rm -rf "$INSTALL_DIR"
echo "  ✅ 文件已删除"

echo ""
echo "  卸载完成。请在 Figma 中手动移除插件："
echo "  Plugins → Development → 右键 Claude Internal → Remove"
echo ""
