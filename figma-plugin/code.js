// Claude Internal in Figma - Plugin Sandbox
figma.showUI(__html__, { width: 520, height: 640, themeColors: true });

// ─── 监听选择变化 ────────────────────────────────────
figma.on('selectionchange', function() {
  sendSelection();
});

// 初始发送一次当前选择
sendSelection();

function sendSelection() {
  var nodes = figma.currentPage.selection;
  if (!nodes.length) {
    figma.ui.postMessage({ type: 'selection', nodes: [] });
    return;
  }

  var data = nodes.map(function(node) {
    return extractNodeInfo(node);
  });

  figma.ui.postMessage({ type: 'selection', nodes: data });
}

function extractNodeInfo(node) {
  var info = {
    id: node.id,
    name: node.name,
    type: node.type,
    width: Math.round(node.width),
    height: Math.round(node.height),
    x: Math.round(node.x),
    y: Math.round(node.y),
  };

  // 获取填充色
  if ('fills' in node && Array.isArray(node.fills) && node.fills.length > 0) {
    info.fills = node.fills.map(function(fill) {
      if (fill.type === 'SOLID') {
        return {
          type: 'SOLID',
          color: rgbToHex(fill.color),
          opacity: fill.opacity !== undefined ? fill.opacity : 1,
        };
      }
      return { type: fill.type };
    });
  }

  // 获取文本内容
  if (node.type === 'TEXT') {
    info.characters = node.characters;
    info.fontSize = node.fontSize;
    info.fontName = node.fontName;
  }

  // 获取自动布局信息
  if ('layoutMode' in node && node.layoutMode !== 'NONE') {
    info.layout = {
      mode: node.layoutMode,
      spacing: node.itemSpacing,
      padding: {
        top: node.paddingTop,
        right: node.paddingRight,
        bottom: node.paddingBottom,
        left: node.paddingLeft,
      },
    };
  }

  // 获取圆角
  if ('cornerRadius' in node && node.cornerRadius !== 0) {
    info.cornerRadius = node.cornerRadius;
  }

  // 获取子节点（最多 2 层深度）
  if ('children' in node && node.children.length > 0) {
    info.children = node.children.map(function(child) {
      return extractChildInfo(child, 1);
    });
  }

  return info;
}

function extractChildInfo(node, depth) {
  var info = {
    name: node.name,
    type: node.type,
    width: Math.round(node.width),
    height: Math.round(node.height),
  };

  if (node.type === 'TEXT') {
    info.characters = node.characters;
    info.fontSize = node.fontSize;
  }

  if ('fills' in node && Array.isArray(node.fills) && node.fills.length > 0) {
    var solidFill = node.fills.find(function(f) { return f.type === 'SOLID'; });
    if (solidFill) {
      info.fillColor = rgbToHex(solidFill.color);
    }
  }

  // 递归子节点（限制深度）
  if (depth < 2 && 'children' in node && node.children.length > 0) {
    info.children = node.children.map(function(child) {
      return extractChildInfo(child, depth + 1);
    });
  }

  return info;
}

function rgbToHex(color) {
  var r = Math.round(color.r * 255);
  var g = Math.round(color.g * 255);
  var b = Math.round(color.b * 255);
  return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
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
