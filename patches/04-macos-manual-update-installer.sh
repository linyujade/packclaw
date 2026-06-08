#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 04-macos-manual-update-installer.sh
#
# Overhauls the update flow for macOS: instead of auto-restart after download,
# extract the zip to .app and let user manually open the installer.
# Also disables code signing/notarization and removes CDN cache refresh from CI.
#
# Run AFTER: 03-optimize-build-caching.sh
#
# Each section is labeled R21–R28. See patches/REQUIREMENTS.md for full details.
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
# R21: Add "ready-to-install" status to update banner state machine
# File: src/update-banner-state.ts
# Desc: Add new status "ready-to-install" and event type "download-ready".
#       macOS downloads and extracts the update, then waits for user to click
#       "open installer" instead of auto-restarting.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R21] Patching update-banner-state.ts ..."
FILE="$WS/src/update-banner-state.ts"
if [ -f "$FILE" ] && ! grep -q 'ready-to-install' "$FILE"; then
  # 1. Expand status type
  sed -i '' 's/"hidden" | "available" | "downloading"/"hidden" | "available" | "downloading" | "ready-to-install"/' "$FILE"

  # 2. Expand event type: add download-ready
  perl -0777 -pi -e \
    's/(\| \{ type: "download-failed" \};)/$1\n  | { type: "download-ready" };/' \
    "$FILE"

  # 3. Add case for "update-not-available" and "download-ready" in reducer
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// Add update-not-available case (was implicitly falling through)
c = c.replace(
  `    case "update-not-available":\n    case "download-finished":\n      return createInitialUpdateBannerState();`,
  `    case "update-not-available":
      return createInitialUpdateBannerState();
    case "download-finished":
      return createInitialUpdateBannerState();
    case "download-ready":
      if (!state.version) {
        return createInitialUpdateBannerState();
      }
      return {
        status: "ready-to-install",
        version: state.version,
        percent: null,
        showBadge: true,
      };`
);

// Remove select comments (non-essential, but keeps diff clean)
c = c.replace(/\/\/ 初始化侧栏更新提示状态：默认隐藏、无进度、无红点。\n/, "");
c = c.replace(/\/\/ 规范化下载进度，避免出现 NaN、负值或超过 100 的异常值。\n/, "");
c = c.replace(/\/\/ 纯状态机：把更新事件映射成 UI 可渲染状态，保持主流程可预测。\n/, "");
c = c.replace(/\/\/ 仅在"已发现更新"时允许启动下载，避免重复触发下载任务。\n/, "");

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'ready-to-install' "$FILE" && ok "R21" || warn "R21: update-banner-state.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R22: macOS manual installer: extract zip instead of quitAndInstall
# File: src/auto-updater.ts
# Desc: On macOS, after downloading the update zip, extract it to find the .app
#       bundle. Store path in pendingUpdateFile. User clicks "open installer"
#       to copy to /Applications and restart. Windows keeps quitAndInstall.
#       Also adds openUpdateInstaller() exported function.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R22] Patching auto-updater.ts ..."
FILE="$WS/src/auto-updater.ts"
if [ -f "$FILE" ] && ! grep -q 'openUpdateInstaller' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Expand imports
c = c.replace(
  `import { dialog } from "electron";`,
  `import { app, dialog, shell } from "electron";\nimport * as child_process from "child_process";\nimport * as fs from "fs";\nimport * as path from "path";`
);

// 2. Add pendingUpdateFile variable after downloadInFlight
c = c.replace(
  `let downloadInFlight: Promise<boolean> | null = null;`,
  `let downloadInFlight: Promise<boolean> | null = null;\nlet pendingUpdateFile: string | null = null;`
);

// 3. Replace update-downloaded handler
c = c.replace(
  /  \/\/ 下载完成后直接重启安装，不再二次确认弹窗。\n  autoUpdater\.on\("update-downloaded", \(\) => \{[\s\S]*?autoUpdater\.quitAndInstall\(false, true\);\n  \}\);/,
  `  // macOS: 下载完成后解压 zip，提取 .app 备用，点击"打开安装包"时直接复制到 /Applications 并重启。
  // Windows: 保持原有 quitAndInstall 行为（NSIS 自动安装正常）。
  autoUpdater.on("update-downloaded", (info) => {
    log.info("[updater] 更新下载完成");
    progressCallback?.(null);

    if (process.platform === "darwin") {
      try {
        const cacheDir = path.join(app.getPath("home"), "Library", "Caches", "packclaw-updater", "pending");
        const infoPath = path.join(cacheDir, "update-info.json");
        if (fs.existsSync(infoPath)) {
          const raw = fs.readFileSync(infoPath, "utf-8");
          const parsed = JSON.parse(raw);
          const srcZip = path.join(cacheDir, parsed.fileName);
          if (fs.existsSync(srcZip)) {
            const extractDir = path.join(cacheDir, "extracted");
            if (fs.existsSync(extractDir)) {
              fs.rmSync(extractDir, { recursive: true, force: true });
            }
            fs.mkdirSync(extractDir, { recursive: true });
            child_process.execSync(\\`unzip -o -q "\${srcZip}" -d "\${extractDir}"\\`);
            const entries = fs.readdirSync(extractDir);
            const appDir = entries.find((e) => e.endsWith(".app"));
            if (appDir) {
              pendingUpdateFile = path.join(extractDir, appDir);
              log.info(\\`[updater] 已解压安装包: \${pendingUpdateFile}\\`);
            } else {
              log.error("[updater] 解压后未找到 .app");
            }
          }
        }
      } catch (copyErr) {
        log.error(\\`[updater] 解压安装包失败: \${formatUpdaterError(copyErr)}\\`);
      }
      publishUpdateBannerState({ type: "download-ready" });
    } else {
      publishUpdateBannerState({ type: "download-finished" });
      log.info("[updater] 准备自动重启安装更新");
      beforeQuitForInstallCallback?.();
      autoUpdater.quitAndInstall(false, true);
    }
  });`
);

// 4. Add openUpdateInstaller function at end of file
c += `

// macOS: 将已解压的 .app 复制到 /Applications 并重启。
// Windows: 不应走到这里（Windows 用 quitAndInstall）。
export async function openUpdateInstaller(): Promise<boolean> {
  if (!pendingUpdateFile) {
    log.warn("[updater] 没有已下载的安装包可打开");
    return false;
  }

  if (process.platform === "darwin") {
    try {
      const appName = path.basename(pendingUpdateFile);
      const destApp = \\`/Applications/\${appName}\\`;
      log.info(\\`[updater] 开始安装: cp -R "\${pendingUpdateFile}" "\${destApp}"\\`);
      child_process.execSync(\\`cp -R "\${pendingUpdateFile}" "\${destApp}"\\`);
      log.info(\\`[updater] 安装完成，准备重启: \${destApp}\\`);
      publishUpdateBannerState({ type: "download-finished" });
      app.relaunch();
      app.exit(0);
      return true;
    } catch (err) {
      log.error(\\`[updater] 安装更新失败: \${formatUpdaterError(err)}\\`);
      return false;
    }
  }

  try {
    await shell.openPath(pendingUpdateFile);
    log.info(\\`[updater] 已打开安装包: \${pendingUpdateFile}\\`);
    publishUpdateBannerState({ type: "download-finished" });
    return true;
  } catch (err) {
    log.error(\\`[updater] 打开安装包失败: \${formatUpdaterError(err)}\\`);
    return false;
  }
}
`;

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'openUpdateInstaller' "$FILE" && ok "R22" || warn "R22: auto-updater.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R23: IPC plumbing for openUpdateInstaller
# Files: src/main.ts, src/preload.ts, chat-ui/ui/src/ui/data/ipc-bridge.ts
# Desc: Wire the openUpdateInstaller function through Electron IPC:
#       main process handler → preload bridge → renderer bridge wrapper.
#       Also update UpdateState status type to include "ready-to-install".
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R23] Patching main.ts, preload.ts, ipc-bridge.ts ..."

# --- main.ts ---
FILE="$WS/src/main.ts"
if [ -f "$FILE" ] && ! grep -q 'app:open-update-installer' "$FILE"; then
  # Add import
  perl -pi -e 's/(downloadAndInstallUpdate,)/$1\n  openUpdateInstaller,/' "$FILE"
  # Add IPC handler after download-and-install
  sed -i '' '/ipcMain.handle("app:download-and-install-update"/a\
ipcMain.handle("app:open-update-installer", () => openUpdateInstaller());' "$FILE"
  grep -q 'app:open-update-installer' "$FILE" && ok "R23: main.ts" || warn "R23: main.ts patch failed"
else
  echo "  (skipped main.ts: already patched or file missing)"
fi

# --- preload.ts ---
FILE="$WS/src/preload.ts"
if [ -f "$FILE" ] && ! grep -q 'openUpdateInstaller' "$FILE"; then
  # Add bridge method after downloadAndInstallUpdate
  sed -i '' '/downloadAndInstallUpdate: () => ipcRenderer.invoke("app:download-and-install-update"),/a\
  openUpdateInstaller: () => ipcRenderer.invoke("app:open-update-installer"),' "$FILE"
  # Update status types
  sed -i '' 's/status: "hidden" | "available" | "downloading"/status: "hidden" | "available" | "downloading" | "ready-to-install"/g' "$FILE"
  grep -q 'openUpdateInstaller' "$FILE" && ok "R23: preload.ts" || warn "R23: preload.ts patch failed"
else
  echo "  (skipped preload.ts: already patched or file missing)"
fi

# --- ipc-bridge.ts ---
FILE="$WS/chat-ui/ui/src/ui/data/ipc-bridge.ts"
if [ -f "$FILE" ] && ! grep -q 'openUpdateInstaller' "$FILE"; then
  # Update UpdateState interface status type
  sed -i '' 's/status: "hidden" | "available" | "downloading"/status: "hidden" | "available" | "downloading" | "ready-to-install"/' "$FILE"
  # Add to PackClawBridgeExtended interface
  sed -i '' '/downloadAndInstallUpdate?: () => Promise<any>;/a\
      openUpdateInstaller?: () => Promise<any>;' "$FILE"
  # Add exported function after downloadAndInstallUpdate
  perl -0777 -pi -e \
    's/(export function downloadAndInstallUpdate\(\): Promise<void> \{\n  return oc\(\)\.downloadAndInstallUpdate\(\) as Promise<void>;\n})/$1\n\nexport function openUpdateInstaller(): Promise<void> {\n  return oc().openUpdateInstaller() as Promise<void>;\n}/' \
    "$FILE"
  grep -q 'openUpdateInstaller' "$FILE" && ok "R23: ipc-bridge.ts" || warn "R23: ipc-bridge.ts patch failed"
else
  echo "  (skipped ipc-bridge.ts: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R24: Sidebar ready-to-install UI + app type updates
# Files: chat-ui/ui/src/ui/sidebar.ts, chat-ui/ui/src/styles.css,
#        chat-ui/ui/src/ui/app-render.ts, chat-ui/ui/src/ui/app.ts
# Desc: When update status is "ready-to-install", sidebar pill shows "open
#       installer" button with download icon and a manual download link.
#       Button click triggers openUpdateInstaller instead of applyUpdate.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R24] Patching sidebar, styles, app-render, app types ..."

# --- app.ts: update type + validator ---
FILE="$WS/chat-ui/ui/src/ui/app.ts"
if [ -f "$FILE" ] && ! grep -q 'ready-to-install' "$FILE"; then
  # Update PackClawUpdateState type
  sed -i '' 's/status: "hidden" | "available" | "downloading"/status: "hidden" | "available" | "downloading" | "ready-to-install"/' "$FILE"
  # Update validator in applyUpdateBannerState
  perl -pi -e \
    's/nextStatus !== "hidden" && nextStatus !== "available" && nextStatus !== "downloading"/nextStatus !== "hidden" \&\& nextStatus !== "available" \&\& nextStatus !== "downloading" \&\& nextStatus !== "ready-to-install"/' \
    "$FILE"
  grep -q 'ready-to-install' "$FILE" && ok "R24: app.ts" || warn "R24: app.ts patch failed"
else
  echo "  (skipped app.ts: already patched or file missing)"
fi

# --- sidebar.ts ---
FILE="$WS/chat-ui/ui/src/ui/sidebar.ts"
if [ -f "$FILE" ] && ! grep -q 'ready-to-install' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Update SidebarProps type: updateStatus
c = c.replace(
  `updateStatus: "hidden" | "available" | "downloading";`,
  `updateStatus: "hidden" | "available" | "downloading" | "ready-to-install";`
);

// 2. Add onOpenUpdateInstaller to SidebarProps
c = c.replace(
  `onApplyUpdate: () => void;\n  onReconnect`,
  `onApplyUpdate: () => void;\n  onOpenUpdateInstaller: () => void;\n  onReconnect`
);

// 3. Update updateLabel ternary
c = c.replace(
  `    : t("sidebar.updateReady");`,
  `    : props.updateStatus === "ready-to-install"\n      ? t("sidebar.updateReadyToInstall")\n      : t("sidebar.updateReady");`
);

// 4. Update button click handler
c = c.replace(
  `@click=\${props.onApplyUpdate}`,
  `@click=\${props.updateStatus === "ready-to-install" ? props.onOpenUpdateInstaller : props.onApplyUpdate}`
);

// 5. Update button icon
c = c.replace(
  `\${props.updateStatus === "downloading" ? icons.loader : icons.zap}`,
  `\${props.updateStatus === "downloading" ? icons.loader : props.updateStatus === "ready-to-install" ? icons.download : icons.zap}`
);

// 6. Add manual download link after button closing tag
c = c.replace(
  `              </button>\n            \` : nothing}\n        <button`,
  `              </button>\n              \${props.updateStatus === "ready-to-install"\n                ? html\`<a href="https://www.packclaw.cn/#download" target="_blank" rel="noopener" class="packclaw-sidebar__manual-dl">\${t("settings.about.manualDownload")}</a>\`\n                : nothing}\n            \` : nothing}\n        <button`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'ready-to-install' "$FILE" && ok "R24: sidebar.ts" || warn "R24: sidebar.ts patch failed"
else
  echo "  (skipped sidebar.ts: already patched or file missing)"
fi

# --- styles.css ---
FILE="$WS/chat-ui/ui/src/styles.css"
if [ -f "$FILE" ] && ! grep -q 'packclaw-sidebar__manual-dl' "$FILE"; then
  perl -0777 -pi -e \
    's/(\.packclaw-sidebar__item--webbridge-repair \{)/.packclaw-sidebar__manual-dl {\n  display: block;\n  text-align: center;\n  font-size: 11px;\n  color: var(--text-muted);\n  text-decoration: none;\n  padding: 4px 14px 8px;\n  transition: color 0.15s;\n}\n.packclaw-sidebar__manual-dl:hover {\n  color: var(--text-primary);\n}\n\n$1/' \
    "$FILE"
  grep -q 'packclaw-sidebar__manual-dl' "$FILE" && ok "R24: styles.css" || warn "R24: styles.css patch failed"
else
  echo "  (skipped styles.css: already patched or file missing)"
fi

# --- app-render.ts ---
FILE="$WS/chat-ui/ui/src/ui/app-render.ts"
if [ -f "$FILE" ] && ! grep -q 'handleOpenUpdateInstaller' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add handleOpenUpdateInstaller function after handleApplyUpdate
c = c.replace(
  `async function handleApplyUpdate(state: AppViewState) {\n  const current = state.updateBannerState;\n  if (current.status !== "available") {\n    return;\n  }\n  try {\n    await window.packclaw?.downloadAndInstallUpdate?.();\n  } catch {\n    // ignore bridge failure\n  }\n}`,
  `async function handleApplyUpdate(state: AppViewState) {\n  const current = state.updateBannerState;\n  if (current.status !== "available") {\n    return;\n  }\n  try {\n    await window.packclaw?.downloadAndInstallUpdate?.();\n  } catch {\n    // ignore bridge failure\n  }\n}\n\nasync function handleOpenUpdateInstaller(state: AppViewState) {\n  const current = state.updateBannerState;\n  if (current.status !== "ready-to-install") {\n    return;\n  }\n  try {\n    await window.packclaw?.openUpdateInstaller?.();\n  } catch {\n    // ignore bridge failure\n  }\n}`
);

// 2. Add onOpenUpdateInstaller to sidebar props
c = c.replace(
  `onApplyUpdate: () => void handleApplyUpdate(state),\n          })}`,
  `onApplyUpdate: () => void handleApplyUpdate(state),\n            onOpenUpdateInstaller: () => void handleOpenUpdateInstaller(state),\n          })}`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'handleOpenUpdateInstaller' "$FILE" && ok "R24: app-render.ts" || warn "R24: app-render.ts patch failed"
else
  echo "  (skipped app-render.ts: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R25: About tab open installer button
# File: chat-ui/ui/src/ui/views/settings/tab-about.ts
# Desc: When update status is "ready-to-install", show version string,
#       "open installer" button, and a manual download link.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R25] Patching tab-about.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-about.ts"
if [ -f "$FILE" ] && ! grep -q 'ready-to-install' "$FILE"; then
  perl -0777 -pi -e \
    's/(\$\{us\.status === "downloading" \? html`\n          <div style="font-size:13px">\$\{t\("settings\.about\.downloading"\)\.replace\("\{percent\}", String\(Math\.round\(us\.percent \?\? 0\)\)\)\}<\/div>\n        ` : nothing\})/$1\n        \${us.status === "ready-to-install" ? html`\n          <div style="font-size:13px;margin-bottom:8px">\${us.version ?? ""}<\/div>\n          <button class="oc-settings__btn oc-settings__btn--primary" @click=\${() => ipc.openUpdateInstaller()}>\n            \${t("settings.about.openInstaller")}\n          <\/button>\n          <div style="margin-top:8px">\n            <a href="https:\/\/www.packclaw.cn\/#download" target="_blank" rel="noopener" style="color:var(--oc-text-link);font-size:13px">\${t("settings.about.manualDownload")}<\/a>\n          <\/div>\n        ` : nothing}/' \
    "$FILE"
  grep -q 'ready-to-install' "$FILE" && ok "R25" || warn "R25: tab-about.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R26: i18n strings for update installer flow
# File: chat-ui/ui/src/ui/i18n.ts
# Desc: Add zh/en strings for the new update installer UI:
#       sidebar.updateReadyToInstall, settings.about.openInstaller,
#       settings.about.manualDownload.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R26] Patching i18n.ts ..."
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && ! grep -q 'sidebar.updateReadyToInstall' "$FILE"; then
  # zh strings
  sed -i '' '/"sidebar.updateDownloading"/a\
    "sidebar.updateReadyToInstall": "点击打开安装包",' "$FILE"
  sed -i '' '/"settings.about.installUpdate"/a\
    "settings.about.openInstaller": "打开安装包",\n    "settings.about.manualDownload": "手动下载",' "$FILE"

  # en strings
  sed -i '' '/"sidebar.updateDownloading": "Downloading update {percent}%"/a\
    "sidebar.updateReadyToInstall": "Open installer",' "$FILE"
  # For en settings.about: add after installUpdate
  sed -i '' '/"settings.about.installUpdate": "Install & Restart"/,/"/a\
    "settings.about.openInstaller": "Open Installer",\n    "settings.about.manualDownload": "Manual Download",' "$FILE"

  grep -q 'sidebar.updateReadyToInstall' "$FILE" && ok "R26" || warn "R26: i18n.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R27: Disable hardenedRuntime and notarize in electron-builder.yml
# File: electron-builder.yml
# Desc: Disable macOS code signing hardening and notarization for development
#       builds. These require valid Apple certificates and notarization creds.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R27] Patching electron-builder.yml ..."
FILE="$WS/electron-builder.yml"
if [ -f "$FILE" ]; then
  sed -i '' 's/^  hardenedRuntime: true/  hardenedRuntime: false/' "$FILE"
  sed -i '' 's/^  notarize: true/  notarize: false/' "$FILE"
  ok "R27"
else
  warn "R27: electron-builder.yml not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R28: Remove CDN cache refresh from CI workflows
# Files: .github/workflows/build-release.yml, .github/workflows/publish-release.yml
# Desc: Remove CDN cache refresh steps (volcengine-cdn-refresh.js) from both
#       CI workflows. TOS CDN cache will expire naturally.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R28] Patching CI workflows ..."

# --- build-release.yml ---
FILE="$WS/.github/workflows/build-release.yml"
if [ -f "$FILE" ] && grep -q 'volcengine-cdn-refresh' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// Remove the CDN refresh step
c = c.replace(
  /      # 刷新 dev 通道 CDN 缓存[\s\S]*?echo "dev 通道 CDN 缓存刷新已提交"\n\n      # dev yml 已上传 TOS \+ 刷新 CDN，从 release 目录移除，不打入 GitHub Release asset/,
  `      # dev yml 已上传 TOS，从 release 目录移除，不打入 GitHub Release asset`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  ! grep -q 'volcengine-cdn-refresh' "$FILE" && ok "R28: build-release.yml" || warn "R28: build-release.yml patch failed"
else
  echo "  (skipped build-release.yml: already patched or file missing)"
fi

# --- publish-release.yml ---
FILE="$WS/.github/workflows/publish-release.yml"
if [ -f "$FILE" ] && grep -q 'volcengine-cdn-refresh' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// Remove the CDN refresh step
c = c.replace(
  /\n      # 刷新 CDN 缓存\n      - name: 刷新 CDN 缓存\n        run: \|\n          node scripts\/volcengine-cdn-refresh\.js \\\n            "https:\/\/\$\{\{ env\.CDN_DOMAIN \}\}\/releases\/latest-mac\.yml" \\\n            "https:\/\/\$\{\{ env\.CDN_DOMAIN \}\}\/releases\/latest\.yml"\n          echo "CDN 缓存刷新已提交"/,
  ""
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  ! grep -q 'volcengine-cdn-refresh' "$FILE" && ok "R28: publish-release.yml" || warn "R28: publish-release.yml patch failed"
else
  echo "  (skipped publish-release.yml: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Patch Summary"
echo "══════════════════════════════════════════════════════════"
if [ -z "$FAILURES" ]; then
  echo "  All 8 patches (R21–R28) applied successfully."
else
  echo "  Failed patches:"
  echo -e "$FAILURES"
  echo ""
  echo "  See patches/REQUIREMENTS.md for manual implementation."
fi
echo "══════════════════════════════════════════════════════════"
