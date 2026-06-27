#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 08-chat-ui-fixes.sh
#
# 聊天界面修复 + 字体大小设置
#
# R41: 修复浮动"新建对话"按钮（侧边栏收起时）
# R42: 修复停止按钮（点击后立即停止 UI，不等网关响应）
# R43: 修复 AI 回复后滚动条跳动（reload 时跳过渐进渲染）
# R44: 增大聊天历史渲染上限（200 → 10000）+ API limit（200 → 1000）
# R45: 用户消息添加复制按钮
# R46: 设置→外观页添加字体大小（基于 Electron setZoomFactor）
#
# Run AFTER: 07-default-skills.sh
#
# See patches/08-chat-ui-fixes.md for details.
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"
FAILURES=""

warn() { echo "  ⚠ [FAIL] $1"; FAILURES="$FAILURES\n  $1"; }
ok()   { echo "  ✓ $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# R41: app-render.ts — 修复浮动"新建对话"按钮
# File: chat-ui/ui/src/ui/app-render.ts
# Desc: generateSessionKey() 从未定义，点击浮动按钮时抛 ReferenceError。
#       改为调用 createNewSession(state)，与侧边栏按钮走同一路径。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R41] Patching app-render.ts (floating new chat button) ..."
FILE="$WS/chat-ui/ui/src/ui/app-render.ts"
if [ -f "$FILE" ] && grep -q 'generateSessionKey' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace(
      "handleSessionChange(state, generateSessionKey())",
      "createNewSession(state)"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'generateSessionKey' "$FILE"; then
    warn "R41: generateSessionKey still present"
  else
    ok "R41 (generateSessionKey → createNewSession)"
  fi
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R42: controllers/chat.ts — 修复停止按钮立即响应
# File: chat-ui/ui/src/ui/controllers/chat.ts
# Desc: abortChatRun 发送 chat.abort RPC 后只等网关回复，UI 不立即停。
#       在 RPC 前调 resetChatStreamState(state) 实现瞬停。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R42] Patching controllers/chat.ts (abort immediate reset) ..."
FILE="$WS/chat-ui/ui/src/ui/controllers/chat.ts"
if [ -f "$FILE" ] && ! grep -q '先立即重置本地状态' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace(
      "  const runId = state.chatRunId;\n  try {",
      "  const runId = state.chatRunId;\n  // 先立即重置本地状态，让 UI 瞬停；不等网关的 state:\"aborted\" 事件\n  resetChatStreamState(state);\n  try {"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q '先立即重置本地状态' "$FILE"; then
    ok "R42 (abortChatRun immediate reset)"
  else
    warn "R42: pattern not found"
  fi
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R43: controllers/chat.ts — 修复 AI 回复后滚动条跳动 + 增大历史 limit
# File: chat-ui/ui/src/ui/controllers/chat.ts
# Desc: loadChatHistory 重载时 chatVisibleMessageCount 被重置为 20，内容缩短导致跳动。
#       通过 isReload 检测：count > 0 时全量显示，跳过渐进渲染。
#       同时把 chat.history RPC limit 从 200 提升到 1000。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R43] Patching controllers/chat.ts (scroll jump fix + limit) ..."
FILE="$WS/chat-ui/ui/src/ui/controllers/chat.ts"
if [ -f "$FILE" ] && ! grep -q 'isReload' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");

    // 1. limit: 200 → 1000
    s = s.replace("limit: 200,", "limit: 1000,");

    // 2. Replace progressive hydration block with smart reload detection
    const oldBlock = `    state.chatVisibleMessageCount = Math.min(
      deduplicated.length,
      INITIAL_CHAT_HISTORY_RENDER_COUNT,
    );
    scheduleChatHistoryHydration(state, requestSessionKey, deduplicated.length);`;

    const newBlock = `    // 切换会话时 chatVisibleMessageCount 被 session-transition 重置为 0 → 走渐进渲染。
    // AI 回复结束后 reload 时 count > 0 → 直接全量显示，避免内容缩短导致滚动条跳动。
    const isReload = state.chatVisibleMessageCount > 0;
    state.chatVisibleMessageCount = isReload
      ? deduplicated.length
      : Math.min(deduplicated.length, INITIAL_CHAT_HISTORY_RENDER_COUNT);
    if (!isReload) {
      scheduleChatHistoryHydration(state, requestSessionKey, deduplicated.length);
    }`;

    s = s.replace(oldBlock, newBlock);
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'isReload' "$FILE"; then
    ok "R43 (scroll jump fix + limit 1000)"
  else
    warn "R43: pattern not found"
  fi
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R44: views/chat.ts — 增大渲染上限
# File: chat-ui/ui/src/ui/views/chat.ts
# Desc: CHAT_HISTORY_RENDER_LIMIT 从 200 提升到 10000
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R44] Patching views/chat.ts (render limit) ..."
FILE="$WS/chat-ui/ui/src/ui/views/chat.ts"
if [ -f "$FILE" ] && grep -q 'CHAT_HISTORY_RENDER_LIMIT = 200' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace("CHAT_HISTORY_RENDER_LIMIT = 200", "CHAT_HISTORY_RENDER_LIMIT = 10000");
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'CHAT_HISTORY_RENDER_LIMIT = 10000' "$FILE"; then
    ok "R44 (render limit 10000)"
  else
    warn "R44: replacement failed"
  fi
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R45: grouped-render.ts — 用户消息添加复制按钮
# File: chat-ui/ui/src/ui/chat/grouped-render.ts
# Desc: 复制按钮条件从 role === "assistant" 改为 (assistant || user)
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R45] Patching grouped-render.ts (user copy button) ..."
FILE="$WS/chat-ui/ui/src/ui/chat/grouped-render.ts"
if [ -f "$FILE" ] && grep -q 'canCopyMarkdown = role === "assistant"' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace(
      /const canCopyMarkdown = role === "assistant" && Boolean/,
      "const canCopyMarkdown = (role === \"assistant\" || role === \"user\") && Boolean"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'role === "user"' "$FILE"; then
    ok "R45 (user copy button)"
  else
    warn "R45: replacement failed"
  fi
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R46: 字体大小设置（Electron setZoomFactor）
# Files: storage.ts, app-settings.ts, tab-appearance.ts, i18n.ts, preload.ts, main.ts
# Desc: 设置→外观页添加字体大小选项（小/默认/大/更大），
#       通过 Electron webContents.setZoomFactor 实现全局等比缩放。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R46] Patching font size setting (6 files) ..."

# R46a: storage.ts — 添加 fontScale 字段
FILE="$WS/chat-ui/ui/src/ui/storage.ts"
if [ -f "$FILE" ] && ! grep -q 'fontScale' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // type
    s = s.replace(
      "  navGroupsCollapsed: Record<string, boolean>;\n};",
      "  navGroupsCollapsed: Record<string, boolean>;\n  fontScale: number;\n};"
    );
    // default
    s = s.replace(
      "    navGroupsCollapsed: {},\n  };",
      "    navGroupsCollapsed: {},\n    fontScale: 1.0,\n  };"
    );
    // parse
    s = s.replace(
      "          : defaults.navGroupsCollapsed,\n    };",
      "          : defaults.navGroupsCollapsed,\n      fontScale:\n        typeof parsed.fontScale === \"number\" &&\n        parsed.fontScale >= 0.85 &&\n        parsed.fontScale <= 2.2\n          ? parsed.fontScale\n          : defaults.fontScale,\n    };"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'fontScale' "$FILE"; then ok "R46a storage.ts"; else warn "R46a storage.ts"; fi
else
  echo "  (skipped R46a storage.ts: already patched or missing)"
fi

# R46b: app-settings.ts — applyFontScale + applySettings + syncThemeWithSettings
FILE="$WS/chat-ui/ui/src/ui/app-settings.ts"
if [ -f "$FILE" ] && ! grep -q 'applyFontScale' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // 1. applySettings: track prevFontScale + apply on change
    s = s.replace(
      /(\s+lastActiveSessionKey: next\.lastActiveSessionKey\?\.trim\(\) \|\| next\.sessionKey\.trim\(\) \|\| "main",\n  \};)/,
      "$1\n  const prevFontScale = host.settings.fontScale;"
    );
    s = s.replace(
      /(\n  host\.applySessionKey = host\.settings\.lastActiveSessionKey;\n\})/,
      "\n  if (normalized.fontScale !== prevFontScale) {\n    applyFontScale(normalized.fontScale);\n  }\n  host.applySessionKey = host.settings.lastActiveSessionKey;\n}"
    );
    // 2. syncThemeWithSettings + applyFontScale function
    s = s.replace(
      "export function syncThemeWithSettings(host: SettingsHost) {\n  host.theme = host.settings.theme ?? \"system\";\n  applyResolvedTheme(host, resolveTheme(host.theme));\n}",
      "export function syncThemeWithSettings(host: SettingsHost) {\n  host.theme = host.settings.theme ?? \"system\";\n  applyResolvedTheme(host, resolveTheme(host.theme));\n  applyFontScale(host.settings.fontScale ?? 1.0);\n}\n\nexport function applyFontScale(fontScale: number): void {\n  const clamped = Math.max(0.85, Math.min(2.2, fontScale));\n  const packclaw = (window as any).packclaw;\n  if (packclaw?.setZoomFactor) {\n    packclaw.setZoomFactor(clamped);\n  }\n}"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'applyFontScale' "$FILE"; then ok "R46b app-settings.ts"; else warn "R46b app-settings.ts"; fi
else
  echo "  (skipped R46b app-settings.ts: already patched or missing)"
fi

# R46c: tab-appearance.ts — 字体大小单选组
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-appearance.ts"
if [ -f "$FILE" ] && ! grep -q 'fontScale' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // 1. state field
    s = s.replace(
      "    showThinking: false,\n    successMsg:",
      "    showThinking: false,\n    fontScale: 1.0,\n    successMsg:"
    );
    // 2. init
    s = s.replace(
      "  s.showThinking = state.settings?.chatShowThinking ?? false;",
      "  s.showThinking = state.settings?.chatShowThinking ?? false;\n  s.fontScale = state.settings?.fontScale ?? 1.0;"
    );
    // 3. handleSave
    s = s.replace(
      "    chatShowThinking: s.showThinking,\n  });",
      "    chatShowThinking: s.showThinking,\n    fontScale: s.fontScale,\n  });"
    );
    // 4. radio group — insert after theme radio group closing </div>
    s = s.replace(
      "      </div>\n\n      <div class=\"oc-settings__form-group\">\n        <oc-toggle-switch",
      "      </div>\n\n      <div class=\"oc-settings__form-group\">\n        <label class=\"oc-settings__label\">${t(\"settings.appearance.fontSize\")}</label>\n        <div class=\"oc-settings__radio-group\">\n          ${([0.85, 1.0, 1.3, 1.6, 2.2] as const).map(v => html`\n            <label class=\"oc-settings__radio\">\n              <input type=\"radio\" name=\"ap-font-scale\" value=${v} .checked=${s.fontScale === v}\n                @change=${() => { s.fontScale = v; state.requestUpdate(); }} />\n              ${t(`fontSize.${v}`)}\n            </label>\n          `)}\n        </div>\n      </div>\n\n      <div class=\"oc-settings__form-group\">\n        <oc-toggle-switch"
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'fontScale' "$FILE"; then ok "R46c tab-appearance.ts"; else warn "R46c tab-appearance.ts"; fi
else
  echo "  (skipped R46c tab-appearance.ts: already patched or missing)"
fi

# R46d: i18n.ts — 中英文标签
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && ! grep -q 'settings.appearance.fontSize' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // ZH
    s = s.replace(
      /("settings\.appearance\.showThinking": "显示思考过程",)/,
      `$1\n    "settings.appearance.fontSize": "字体大小",\n\n    "fontSize.0.85": "小",\n    "fontSize.1": "默认",\n    "fontSize.1.3": "大",\n    "fontSize.1.6": "更大",\n    "fontSize.2.2": "超大",`
    );
    // EN
    s = s.replace(
      /("settings\.appearance\.showThinking": "Show thinking process",)/,
      `$1\n    "settings.appearance.fontSize": "Font Size",\n\n    "fontSize.0.85": "Small",\n    "fontSize.1": "Default",\n    "fontSize.1.3": "Large",\n    "fontSize.1.6": "Extra Large",\n    "fontSize.2.2": "Huge",`
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'settings.appearance.fontSize' "$FILE"; then ok "R46d i18n.ts"; else warn "R46d i18n.ts"; fi
else
  echo "  (skipped R46d i18n.ts: already patched or missing)"
fi

# R46e: preload.ts — setZoomFactor IPC bridge
FILE="$WS/src/preload.ts"
if [ -f "$FILE" ] && ! grep -q 'setZoomFactor' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace(
      `  openPath: (path: string) => ipcRenderer.invoke("app:open-path", path),`,
      `  openPath: (path: string) => ipcRenderer.invoke("app:open-path", path),\n  setZoomFactor: (factor: number) => ipcRenderer.invoke("app:set-zoom-factor", factor),`
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'setZoomFactor' "$FILE"; then ok "R46e preload.ts"; else warn "R46e preload.ts"; fi
else
  echo "  (skipped R46e preload.ts: already patched or missing)"
fi

# R46f: main.ts — setZoomFactor IPC handler
FILE="$WS/src/main.ts"
if [ -f "$FILE" ] && ! grep -q 'app:set-zoom-factor' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    s = s.replace(
      `ipcMain.handle("app:open-path", (_e, filePath: string) => shell.openPath(filePath));`,
      `ipcMain.handle("app:open-path", (_e, filePath: string) => shell.openPath(filePath));
ipcMain.handle("app:set-zoom-factor", (e, factor: number) => {
  const win = BrowserWindow.fromWebContents(e.sender);
  if (win) {
    const clamped = Math.max(0.85, Math.min(2.2, factor));
    win.webContents.setZoomFactor(clamped);
  }
});`
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  if grep -q 'app:set-zoom-factor' "$FILE"; then ok "R46f main.ts"; else warn "R46f main.ts"; fi
else
  echo "  (skipped R46f main.ts: already patched or missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
if [ -n "$FAILURES" ]; then
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  ⚠  Some patches FAILED. Review and fix manually:         ║"
  echo "╠════════════════════════════════════════════════════════════╣"
  printf "║  %-56s  ║\n" $(echo -e "$FAILURES" | grep -v "^$")
  echo "╚════════════════════════════════════════════════════════════╝"
else
  echo ""
  echo "✅ All chat UI patches applied successfully."
fi
