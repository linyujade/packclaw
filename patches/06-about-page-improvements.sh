#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 06-about-page-improvements.sh
#
# 1. 设置→软件更新页添加"手动下载"模块（链接打开系统默认浏览器）
# 2. 侧边栏更新提示点击后跳转到设置→软件更新页（而非直接下载）
#
# Run AFTER: 05-skill-store-enhancements.sh
#
# Each section is labeled R37–R39. See patches/06-about-page-improvements.md.
# If a patch fails, the script warns but continues. Check FAILURES at the end.
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"
FAILURES=""

warn() { echo "  ⚠ [FAIL] $1"; FAILURES="$FAILURES\n  $1"; }
ok()   { echo "  ✓ $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# R37: tab-about.ts — 添加"手动下载"模块
# File: chat-ui/ui/src/ui/views/settings/tab-about.ts
# Desc: 在软件更新卡片下方添加"手动下载"卡片，链接用 ipc.openExternal
#       打开系统默认浏览器（颜色用 --accent 红色主题色）。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R37] Patching tab-about.ts (manual download card) ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-about.ts"
if [ -f "$FILE" ] && ! grep -q 'gotoWebsite' "$FILE"; then
  perl -0777 -pi -e \
    's/(` : nothing)\n      <\/div>\n    <\/div>;\n  \};/$1\n      <\/div>\n\n      <!-- Manual Download -->\n      <div class="oc-settings__card">\n        <div class="oc-settings__card-title">${t("settings.about.manualDownload")}<\/div>\n        <a style="color:var(--accent);font-size:13px;cursor:pointer" \@click=${(e: Event) => { e.preventDefault(); ipc.openExternal("https:\/\/www.packclaw.cn\/#download"); }}>${t("settings.about.gotoWebsite")}<\/a>\n      <\/div>\n    <\/div>;\n  };/s' \
    "$FILE"
  grep -q 'gotoWebsite' "$FILE" && ok "R37" || warn "R37: tab-about.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R38: i18n.ts — 添加 gotoWebsite i18n key
# File: chat-ui/ui/src/ui/i18n.ts
# Desc: 添加"进入网站下载"/"Go to website to download"到 zh + en。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R38] Patching i18n.ts (gotoWebsite key) ..."
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && ! grep -q 'settings.about.gotoWebsite' "$FILE"; then
  # Chinese
  perl -pi -e \
    's/("settings\.about\.manualDownload": "手动下载",)/$1\n    "settings.about.gotoWebsite": "进入网站下载",/' \
    "$FILE"
  # English
  perl -pi -e \
    's/("settings\.about\.manualDownload": "Manual Download",)/$1\n    "settings.about.gotoWebsite": "Go to website to download",/' \
    "$FILE"
  grep -q 'settings.about.gotoWebsite' "$FILE" && ok "R38" || warn "R38: i18n key not added"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R39: app-render.ts — 侧边栏更新提示点击跳转到设置页
# File: chat-ui/ui/src/ui/app-render.ts
# Desc: handleApplyUpdate 不再直接调用 downloadAndInstallUpdate，
#       改为 openSettingsView(state, "about") 跳转到设置→软件更新页。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R39] Patching app-render.ts (sidebar update → settings) ..."
FILE="$WS/chat-ui/ui/src/ui/app-render.ts"
if [ -f "$FILE" ] && ! grep -q 'openSettingsView(state, "about")' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");
    // Replace handleApplyUpdate body: from status check + download to openSettingsView
    s = s.replace(
      /async function handleApplyUpdate\(state: AppViewState\) \{\n  const current = state\.updateBannerState;\n  if \(current\.status !== "available"\) \{\n    return;\n  \}\n  try \{\n    await window\.packclaw\?\.downloadAndInstallUpdate\?\.\(\);\n  \} catch \{\n    \/\/ ignore bridge failure[^\n]*\n  \}\n\}/,
      `async function handleApplyUpdate(state: AppViewState) {\n  openSettingsView(state, "about");\n}`
    );
    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  grep -q 'openSettingsView(state, "about")' "$FILE" && ok "R39" || warn "R39: app-render.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
if [ -n "$FAILURES" ]; then
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  ⚠  Some patches FAILED. Review and fix manually:         ║"
  echo "╠════════════════════════════════════════════════════════════╣"
  printf "║  %-56s  ║\n" $(echo -e "$FAILURES" | grep -v '^$')
  echo "╚════════════════════════════════════════════════════════════╝"
else
  echo ""
  echo "✅ All about page improvement patches applied successfully."
fi
