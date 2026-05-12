// Claude Internal in Figma - Plugin Sandbox
figma.showUI(__html__, { width: 520, height: 640, themeColors: true });

figma.ui.onmessage = function(msg) {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'close') figma.closePlugin();
  if (msg.type === 'ui-resize') {
    var w = Math.max(360, Math.min(1600, Math.round(msg.width || 520)));
    var h = Math.max(400, Math.min(2000, Math.round(msg.height || 640)));
    figma.ui.resize(w, h);
  }
};
