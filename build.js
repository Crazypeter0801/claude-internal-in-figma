/**
 * Build script: reads xterm.js + addon-fit from node_modules,
 * inlines them into ui.html for Figma plugin compatibility.
 *
 * Run: npm run build (after npm install)
 */

const fs = require('fs');
const path = require('path');

const PLUGIN_DIR = path.join(__dirname, 'figma-plugin');

// Read xterm sources from node_modules
const xtermJS = fs.readFileSync(
  path.join(__dirname, 'node_modules', 'xterm', 'lib', 'xterm.js'),
  'utf8'
);
const fitAddonJS = fs.readFileSync(
  path.join(__dirname, 'node_modules', '@xterm', 'addon-fit', 'lib', 'addon-fit.js'),
  'utf8'
);
const xtermCSS = fs.readFileSync(
  path.join(__dirname, 'node_modules', 'xterm', 'css', 'xterm.css'),
  'utf8'
);

// Read the template
const template = fs.readFileSync(path.join(__dirname, 'ui-template.html'), 'utf8');

// Replace placeholders
const output = template
  .replace('/* __XTERM_CSS__ */', xtermCSS)
  .replace('/* __XTERM_JS__ */', xtermJS)
  .replace('/* __FIT_ADDON_JS__ */', fitAddonJS);

// Write final ui.html
fs.mkdirSync(PLUGIN_DIR, { recursive: true });
fs.writeFileSync(path.join(PLUGIN_DIR, 'ui.html'), output, 'utf8');

console.log('✓ Built figma-plugin/ui.html with inlined xterm.js');
console.log(`  Size: ${(Buffer.byteLength(output) / 1024).toFixed(1)} KB`);
