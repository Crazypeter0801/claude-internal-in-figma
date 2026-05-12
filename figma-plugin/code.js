// Claude Internal in Figma - Plugin Sandbox
figma.showUI(__html__, { width: 520, height: 640, themeColors: true });

// ─── 获取文件信息 ────────────────────────────────────
var fileKey = '';
try {
  fileKey = figma.fileKey || '';
} catch (e) {}

// ─── 监听选择变化 ────────────────────────────────────
figma.on('selectionchange', function() {
  sendSelection();
});

// 初始发送一次
sendSelection();

function sendSelection() {
  var nodes = figma.currentPage.selection;
  if (!nodes.length) {
    figma.ui.postMessage({ type: 'selection', nodes: [], fileKey: fileKey });
    return;
  }

  var data = nodes.map(function(node) {
    // 构造 Figma URL 格式的 node-id（用 - 替换 :）
    var nodeIdForUrl = node.id.replace(':', '-');
    var figmaUrl = '';
    if (fileKey) {
      figmaUrl = 'https://figma.com/design/' + fileKey + '/?node-id=' + nodeIdForUrl;
    }

    return {
      id: node.id,
      name: node.name,
      type: node.type,
      width: Math.round(node.width),
      height: Math.round(node.height),
      figmaUrl: figmaUrl,
    };
  });

  figma.ui.postMessage({ type: 'selection', nodes: data, fileKey: fileKey });
}

// ─── 处理来自 UI 的消息 ──────────────────────────────
figma.ui.onmessage = function(msg) {
  if (!msg || typeof msg !== 'object') return;

  if (msg.type === 'close') figma.closePlugin();

  if (msg.type === 'ui-resize') {
    var w = Math.max(360, Math.min(1600, Math.round(msg.width || 520)));
    var h = Math.max(400, Math.min(2000, Math.round(msg.height || 640)));
    figma.ui.resize(w, h);
  }

  if (msg.type === 'get-selection') {
    sendSelection();
  }
};
