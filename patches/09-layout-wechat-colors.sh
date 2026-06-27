#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 09-layout-wechat-colors.sh
#
# 大字号布局修复 + 微信风格聊天气泡配色 + 字体范围扩展
#
# R47: chat-main min-width 400px→0，修复大字号下消息内容被裁剪
# R48: card.chat 加 padding:0，消息区与输入框等宽
# R49: chat-group-messages flex:1 去掉 max-width 限制
# R50: chat-bubble display:block + overflow-wrap:anywhere
# R51: sidebar brand/footer/nav flex-shrink:0 防压缩
# R52: 浅色主题微信配色（用户绿色、AI浅灰、深色文字）
# R53: 字体缩放范围 1.3→2.2（新增更大/超大选项）
#
# Run AFTER: 08-chat-ui-fixes.sh
#
# See patches/09-layout-wechat-colors.md for details.
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"
FAILURES=""

warn() { echo "  ⚠ [FAIL] $1"; FAILURES="$FAILURES\n  $1"; }
ok()   { echo "  ✓ $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# R47-R52: styles.css — 布局修复 + 微信配色
# File: chat-ui/ui/src/styles.css
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R47-R52] Patching styles.css (layout + wechat colors) ..."
FILE="$WS/chat-ui/ui/src/styles.css"
if [ -f "$FILE" ]; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    let changed = false;

    // R49: .chat-group-messages — 去掉 max-width，改为 flex:1
    if (s.includes("max-width: min(900px, calc(100% - 60px))")) {
      s = s.replace(
        "  max-width: min(900px, calc(100% - 60px))",
        "  min-width: 0;\n  flex: 1"
      );
      changed = true;
    }

    // R50: .chat-bubble (第一处 ~line 1872) — display:block + overflow-wrap
    if (s.includes("display: inline-block;\n  border: 1px solid transparent;\n  background: var(--card);\n  border-radius: var(--radius-lg);\n  padding: 10px 14px;\n  box-shadow: none;\n  transition: background .15s ease-out, border-color .15s ease-out;\n  max-width: 100%;\n  word-wrap: break-word")) {
      s = s.replace(
        "display: inline-block;\n  border: 1px solid transparent;\n  background: var(--card);\n  border-radius: var(--radius-lg);\n  padding: 10px 14px;\n  box-shadow: none;\n  transition: background .15s ease-out, border-color .15s ease-out;\n  max-width: 100%;\n  word-wrap: break-word",
        "display: block;\n  width: auto;\n  border: 1px solid transparent;\n  background: var(--card);\n  border-radius: var(--radius-lg);\n  padding: 10px 14px;\n  box-shadow: none;\n  transition: background .15s ease-out, border-color .15s ease-out;\n  overflow-wrap: anywhere;\n  word-break: break-word"
      );
      changed = true;
    }

    // R52: 替换旧的用户消息配色为微信风格（仅浅色主题）
    const oldUserColors = `.chat-group.user .chat-bubble {
  background: var(--accent-subtle);
  border-color: transparent
}

:root[data-theme=light] .chat-group.user .chat-bubble {
  border-color: #ea580c33;
  background: #fb923c1f
}

.chat-group.user .chat-bubble:hover {
  background: #ff4d4d26
}`;

    const newUserColors = `/* ── 微信风格配色：仅浅色主题 ── */

/* AI 回复消息：浅灰背景、深色文字 */
:root[data-theme=light] .chat-group.assistant .chat-bubble:not(:has(.chat-tool-msg-collapse)) {
  background: #efefef;
  color: #1a1a1a;
  --chat-text: #1a1a1a
}

/* 用户消息：绿色背景、深色文字 */
:root[data-theme=light] .chat-group.user .chat-bubble {
  background: #95ec69;
  border-color: transparent;
  color: #1a1a1a;
  --chat-text: #1a1a1a
}`;

    if (s.includes(oldUserColors)) {
      s = s.replace(oldUserColors, newUserColors);
      changed = true;
    }

    // R47: .chat-main min-width 400px → 0
    if (s.includes(".chat-main {\n  min-width: 400px;")) {
      s = s.replace(".chat-main {\n  min-width: 400px;", ".chat-main {\n  min-width: 0;");
      changed = true;
    }

    // R50 (第二处): .chat-bubble (~line 3762) 加 width:fit-content
    if (s.includes("  padding: 10px 14px;\n  min-width: 0\n}")) {
      s = s.replace(
        "  padding: 10px 14px;\n  min-width: 0\n}",
        "  padding: 10px 14px;\n  min-width: 0;\n  max-width: 100%;\n  width: fit-content;\n  overflow-wrap: anywhere;\n  word-break: break-word\n}"
      );
      changed = true;
    }

    // R48: .packclaw-content>.card.chat 加 padding:0
    if (s.includes(".packclaw-content>.card.chat {\n  flex: 1;\n  border-radius: 0;\n  border: none;\n  margin: 0;\n}")) {
      s = s.replace(
        ".packclaw-content>.card.chat {\n  flex: 1;\n  border-radius: 0;\n  border: none;\n  margin: 0;\n}",
        ".packclaw-content>.card.chat {\n  flex: 1;\n  border-radius: 0;\n  border: none;\n  margin: 0;\n  padding: 0\n}"
      );
      changed = true;
    }

    // R51: .packclaw-sidebar__brand 加 flex-shrink:0
    if (s.includes("-webkit-app-region: drag;\n}\n\n.packclaw-sidebar__brand-main")) {
      s = s.replace(
        "-webkit-app-region: drag;\n}\n\n.packclaw-sidebar__brand-main",
        "-webkit-app-region: drag;\n  flex-shrink: 0\n}\n\n.packclaw-sidebar__brand-main"
      );
      changed = true;
    }

    // R51: .packclaw-sidebar__nav > :not(.session-list) 加 flex-shrink:0
    if (!s.includes("packclaw-sidebar__nav > :not(.packclaw-sidebar__session-list)")) {
      // 插入在 .packclaw-sidebar__section-title 之前
      s = s.replace(
        ".packclaw-sidebar__section-title {",
        "/* 防止大字号时导航项被压缩，只有会话列表区域可滚动 */\n.packclaw-sidebar__nav > :not(.packclaw-sidebar__session-list) {\n  flex-shrink: 0;\n}\n\n.packclaw-sidebar__section-title {"
      );
      changed = true;
    }

    // R51: .packclaw-sidebar__footer 加 flex-shrink:0
    if (s.includes(".packclaw-sidebar__footer {\n  display: flex;\n  flex-direction: column;\n  gap: 6px;\n}")) {
      s = s.replace(
        ".packclaw-sidebar__footer {\n  display: flex;\n  flex-direction: column;\n  gap: 6px;\n}",
        ".packclaw-sidebar__footer {\n  display: flex;\n  flex-direction: column;\n  gap: 6px;\n  flex-shrink: 0\n}"
      );
      changed = true;
    }

    if (changed) {
      fs.writeFileSync(f, s, "utf8");
    }
  ' "$FILE"

  # 验证关键改动
  if grep -q 'min-width: 0;' "$FILE" && grep -q '#95ec69' "$FILE"; then ok "R47-R52 styles.css"; else warn "R47-R52 styles.css verification failed"; fi
else
  echo "  (skipped: styles.css missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R53: 字体缩放范围 1.3→2.2（兼容 patch 08 旧值）
# Files: storage.ts, app-settings.ts, tab-appearance.ts, i18n.ts, main.ts
# Desc: patch 08 可能已用旧范围(1.3)应用，此处确保更新到 2.2
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R53] Updating font scale range 1.3 → 2.2 ..."

# R53a: storage.ts
FILE="$WS/chat-ui/ui/src/ui/storage.ts"
if [ -f "$FILE" ] && grep -q 'parsed.fontScale <= 1.3' "$FILE"; then
  sed -i '' 's/parsed\.fontScale <= 1\.3/parsed.fontScale <= 2.2/' "$FILE"
  grep -q '<= 2.2' "$FILE" && ok "R53a storage.ts" || warn "R53a storage.ts"
else
  echo "  (skipped R53a storage.ts: already updated or missing)"
fi

# R53b: app-settings.ts
FILE="$WS/chat-ui/ui/src/ui/app-settings.ts"
if [ -f "$FILE" ] && grep -q 'Math.min(1.3,' "$FILE"; then
  sed -i '' 's/Math\.min(1\.3,/Math.min(2.2,/' "$FILE"
  grep -q 'Math.min(2.2,' "$FILE" && ok "R53b app-settings.ts" || warn "R53b app-settings.ts"
else
  echo "  (skipped R53b app-settings.ts: already updated or missing)"
fi

# R53c: tab-appearance.ts — 更新选项列表
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-appearance.ts"
if [ -f "$FILE" ] && grep -q '0.85, 1.0, 1.1, 1.2' "$FILE"; then
  sed -i '' 's/0\.85, 1\.0, 1\.1, 1\.2/0.85, 1.0, 1.3, 1.6, 2.2/' "$FILE"
  grep -q '1.3, 1.6, 2.2' "$FILE" && ok "R53c tab-appearance.ts" || warn "R53c tab-appearance.ts"
else
  echo "  (skipped R53c tab-appearance.ts: already updated or missing)"
fi

# R53d: i18n.ts — 更新字体大小标签
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && grep -q 'fontSize.1.1' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // ZH
    s = s.replace(
      /"fontSize\.1\.1": "大",\n    "fontSize\.1\.2": "更大",/,
      `"fontSize.1.3": "大",\n    "fontSize.1.6": "更大",\n    "fontSize.2.2": "超大",`
    );
    // EN
    s = s.replace(
      /"fontSize\.1\.1": "Large",\n    "fontSize\.1\.2": "Extra Large",/,
      `"fontSize.1.3": "Large",\n    "fontSize.1.6": "Extra Large",\n    "fontSize.2.2": "Huge",`
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  grep -q 'fontSize.2.2' "$FILE" && ok "R53d i18n.ts" || warn "R53d i18n.ts"
else
  echo "  (skipped R53d i18n.ts: already updated or missing)"
fi

# R53e: main.ts — IPC handler clamp
FILE="$WS/src/main.ts"
if [ -f "$FILE" ] && grep -q 'Math.min(1.3,' "$FILE"; then
  sed -i '' 's/Math\.min(1\.3,/Math.min(2.2,/' "$FILE"
  grep -q 'Math.min(2.2,' "$FILE" && ok "R53e main.ts" || warn "R53e main.ts"
else
  echo "  (skipped R53e main.ts: already updated or missing)"
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
  echo "✅ All layout + wechat color patches applied successfully."
fi
