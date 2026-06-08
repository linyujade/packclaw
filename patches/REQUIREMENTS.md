# PackClaw Customization Requirements

> When the patch script (`02-apply-packclaw-customizations.sh`) fails on a new upstream sync,
> use this document to re-implement each requirement point from scratch.
>
> Each requirement has: **file path**, **description**, **key code snippets**, and **how to verify**.

---

## R01: 51key Provider Preset in Backend

**File:** `workspace/src/provider-config.ts`

**Description:** Add 51key as a provider preset so the backend recognizes it. Also add a no-op verify case so the verify flow doesn't crash.

**Changes:**
1. In `PROVIDER_PRESETS` object, add after the `google` entry:
```typescript
"51key": { baseUrl: "https://api.lmdone.com/v1", api: "openai-completions" },
```

2. In the `verify` function's switch statement, add a case after `google`:
```typescript
case "51key":
  break;
```

**Verify:** `tsc --noEmit` passes. 51key appears in provider config.

---

## R02: 51key in Setup Constants

**File:** `workspace/chat-ui/ui/src/ui/views/setup/setup-constants.ts`

**Description:** Import 51key config, add it to the PROVIDERS map, make it the first/default provider in display order, and add its label to i18n.

**Changes:**
1. Add import at top (after existing imports):
```typescript
import { PROVIDER_51KEY, KEY_51KEY_LOCAL_STATE, API_51KEY } from "./provider-51key-config.ts";
export { KEY_51KEY_LOCAL_STATE, API_51KEY };
```

2. Add 51key to PROVIDERS map (after `google` entry, before `custom`):
```typescript
"51key": PROVIDER_51KEY,
```

3. Change PROVIDER_DISPLAY_ORDER to put 51key first and remove moonshot:
```typescript
export const PROVIDER_DISPLAY_ORDER = ["51key", "anthropic", "openai", "google", "custom"] as const;
```

4. In `getProviderLabels()`, add labels for 51key and moonshot:
```typescript
"51key": t("setup.provider.label.51key"),
moonshot: t("setup.provider.label.moonshot"),
```

**Verify:** Setup wizard shows 51key as first tab.

---

## R03: 51key Setup Wizard Section

**File:** `workspace/chat-ui/ui/src/ui/views/setup/setup-step2-provider.ts`

**Description:** Make 51key the default provider in setup. When 51key is selected, show the 51key-specific login section instead of the standard API key form. Add a "Verify & Continue" button for 51key.

**Changes:**
1. Add imports at top:
```typescript
import {
  init51keyDefaults, ensure51keyStateLoaded, handle51keyProviderChange,
  handle51keyVerifyAndContinue, render51keySection,
} from "./setup-51key-section.ts";
```

2. Change default `currentProvider` from `"moonshot"` to `"51key"` in the `s` state object.

3. Add `modelAlias: ""` field to the state object.

4. Spread 51key defaults into state: `...init51keyDefaults(),`

5. In `onProviderChange` function, add 51key branch:
```typescript
if (provider === "51key") {
  handle51keyProviderChange(s, state);
} else {
  const models = getModels();
  if (models.length) s.modelId = models[0];
}
```

6. In `renderStep2`, add at the start of the function body:
```typescript
if (s.currentProvider === "51key") ensure51keyStateLoaded(s);
```

7. Add `const is51key = s.currentProvider === "51key";`

8. Wrap the provider-specific form section: when `is51key`, show `render51keySection(s, state)` instead of moonshot/custom/openai/google forms.

9. Change error message visibility for 51key:
```typescript
${!s["51keyApiKeyRetrieved"] ? html`<oc-message-box ...>` : nothing}
```

10. Change verify button: show standard verify only when `!isOAuth && !is51key`. Add 51key verify button:
```typescript
${is51key && s["51keyApiKeyRetrieved"] ? html`
  <button ... @click=${() => handle51keyVerifyAndContinue(s, state, goToStep)}>
    ${s.verifying ? "..." : t("setup.provider.51key.verifyAndContinue")}
  </button>
` : nothing}
```

**Verify:** Setup wizard step 2 shows 51key email login form by default.

---

## R04: 51key Settings Provider Tab

**File:** `workspace/chat-ui/ui/src/ui/views/settings/tab-provider.ts`

**Description:** Add 51key-specific rendering in the settings provider tab. When user selects 51key, show the 51key login/settings section instead of the standard form.

**Changes:**
1. Add imports at top:
```typescript
import { init51keyDefaults, load51keyState, handle51keyProviderChange } from "../setup/setup-51key-section.ts";
import { render51keySettingsSection } from "./settings-51key-section.ts";
```

2. Change default `currentProvider` from `"moonshot"` to `"51key"` in `createProviderState()`.

3. Add `...init51keyDefaults()` to the state object.

4. In the init/load function (where saved config is loaded), add 51key state loading:
```typescript
if (s.currentProvider === "51key") {
  load51keyState(s);
  if (!s.modelId) {
    const m = PROVIDERS["51key"]?.models ?? [];
    if (m.length) s.modelId = m[0];
  }
}
```

5. In `onProviderChange`, add 51key branch:
```typescript
if (provider === "51key") {
  handle51keyProviderChange(s, state);
} else {
  const models = getModels();
  if (models.length) s.modelId = models[0];
  const saved = lookupSavedProvider(provider);
  fillSavedProviderFields(saved);
}
```

6. In the render function, wrap the provider form: when `s.currentProvider === "51key"`, render `render51keySettingsSection(...)` instead of the standard form. Close the conditional with `` } ` `` before the closing `</div>` of the form container.

**Verify:** Settings → Provider tab shows 51key login form when 51key is selected.

---

## R05: 51key Empty Response Balance Check

**File:** `workspace/chat-ui/ui/src/ui/chat/grouped-render.ts`

**Description:** When 51key returns an empty response (balance depleted), show a "balance low" message with a recharge link instead of nothing.

**Changes:**
1. Add import at top:
```typescript
import { render51keyEmptyResponse } from "./chat-51key-balance.ts";
```

2. In the function that renders assistant messages, after the `if (!markdown && !hasToolCards && !hasImages)` check, add:
```typescript
const empty51key = render51keyEmptyResponse(m, bubbleClasses);
if (empty51key) return empty51key;
```
This should be right before the existing `return nothing;` in that block.

**Verify:** When 51key balance is 0, chat shows "余额不足" message with recharge link.

---

## R06: 51key i18n Integration

**File:** `workspace/chat-ui/ui/src/ui/i18n.ts`

**Description:** Import the 51key i18n dictionary and merge it into the main translation dict. Also update the channels description to remove "Kimi" mention.

**Changes:**
1. Add import at top of file:
```typescript
import { i18n51key } from "./i18n-51key.ts";
```

2. In the Chinese dict (`zh`), change:
```
"settings.channels.desc": "连接微信、飞书、企业微信、钉钉、Kimi 或 QQ，从聊天软件远程控制 PackClaw"
```
to:
```
"settings.channels.desc": "连接微信、飞书、企业微信、钉钉 或 QQ，从聊天软件远程控制 PackClaw"
```

3. After the `dict` object definition, add merge code:
```typescript
for (const locale of Object.keys(i18n51key) as Locale[]) {
  Object.assign(dict[locale], i18n51key[locale]);
}
```

**Verify:** All 51key UI strings render in both Chinese and English.

---

## R07: Disable KimiClaw Channel & Remove Search Tab

**File:** `workspace/chat-ui/ui/src/ui/views/settings/settings-constants.ts`

**Description:** Comment out the kimiclaw channel entry (disable Kimi channel integration). Remove the "search" tab from settings navigation.

**Changes:**
1. Comment out the kimiclaw channel entry:
```typescript
// { id: "kimiclaw", labelKey: "settings.channels.kimiclaw", descKey: "settings.channels.kimiclaw.desc" },
```

2. Remove the line `{ id: "search", labelKey: "settings.nav.search" },` from `SETTINGS_TABS`.

**Verify:** Settings → Channels does not show Kimi. Settings nav does not show Search tab.

---

## R08: Remove Webbridge Radio Option

**File:** `workspace/chat-ui/ui/src/ui/views/settings/tab-advanced.ts`

**Description:** Remove the "webbridge" radio button from the browser profile section, leaving only "openclaw" and "none" options.

**Changes:** Delete the 7-line block containing the webbridge radio input and its label.

The block to remove looks like:
```html
<label class="oc-settings__radio">
  <input type="radio" name="adv-browser" value="webbridge"
    .checked=${s.browserMode === "webbridge"}
    ?disabled=${s.precheckInflight}
    @change=${() => onBrowserModeChange(state, "webbridge")} />
  ${t("settings.advanced.browserWebbridge")}
</label>
<label class="oc-settings__radio">
```
Remove the first `<label>...</label>` for webbridge, keeping the opening `<label>` of the next option.

**Verify:** Settings → Advanced → browser profile only shows openclaw and none.

---

## R09: Remove Kimi Embedding Toggle

**File:** `workspace/chat-ui/ui/src/ui/views/settings/tab-memory.ts`

**Description:** Remove the Kimi embedding toggle from the memory settings tab. This feature depends on Kimi which is disabled in PackClaw.

**Changes:**
1. Remove `embeddingEnabled` and `isKimiCodeConfigured` from state object
2. Remove their loading in init function
3. Remove them from `handleSave` call
4. Remove the `embeddingStatus` computed variable
5. Remove the embedding toggle `<oc-toggle-switch>` block and its status hint

**Verify:** Settings → Memory only shows session memory toggle.

---

## R10: Auto-Disable KimiClaw Plugin on Startup

**File:** `workspace/src/main.ts`

**Description:** Add a migration function that automatically sets `kimi-claw` plugin's `enabled` field to `false` on every startup. This prevents background API usage.

**Changes:**
1. Add new function `migrateDisableKimiClaw()` after the existing migration functions:
```typescript
function migrateDisableKimiClaw(): void {
  try {
    const config = readUserConfig();
    const entry = config?.plugins?.entries?.["kimi-claw"];
    if (!entry || typeof entry !== "object") return;
    if ((entry as any).enabled === false) return;
    (entry as any).enabled = false;
    writeUserConfig(config);
    log.info("[migrate] 已禁用 kimi-claw 插件（防止后台消耗 API 额度）");
  } catch {
    // 迁移失败不阻塞启动
  }
}
```

2. Call `migrateDisableKimiClaw();` in BOTH the "fresh" and "legacy-packclaw" startup paths (after `migrateKimiPluginDeviceId()`).

**Verify:** On startup, kimi-claw plugin is forced to disabled in user config.

---

## R11: Update Channels Description (Settings JS)

**File:** `workspace/settings/settings.js`

**Description:** Remove "Kimi" from the channels description in both English and Chinese i18n strings.

**Changes:**
1. English: Change `"Connect WeChat, Feishu, WeCom, DingTalk, Kimi, or QQ to control PackClaw remotely from your messaging app"` to `"Connect WeChat, Feishu, WeCom, DingTalk, or QQ to control PackClaw remotely from your messaging app"`

2. Chinese: Change `"连接微信、飞书、企业微信、钉钉、Kimi 或 QQ，从聊天软件远程控制 PackClaw"` to `"连接微信、飞书、企业微信、钉钉 或 QQ，从聊天软件远程控制 PackClaw"`

**Verify:** Settings → Remote Control description no longer mentions Kimi.

---

## R12: Feedback Submission via SMTP Email

**File:** `workspace/src/feedback-ipc.ts`

**Description:** Replace the upstream multipart HTTP + SSE feedback submission with nodemailer SMTP email. Feedback is sent to `linyujade@163.com` via `smtp.163.com:465`.

**Changes:**
1. Add import: `import * as nodemailer from "nodemailer";`

2. Replace the `feedback:submit` handler's multipart construction and HTTP posting with:
   - Build an HTML email body with feedback content, user email, and device metadata
   - Collect screenshots and log files as email attachments
   - Send via nodemailer with SMTP config:
     ```typescript
     host: "smtp.163.com", port: 465, secure: true,
     auth: { user: "linyujade@163.com", pass: "CKVZGjpsVrntzHge" }
     ```
   - Return `{ ok: true, id: Date.now() }` on success
   - Return `{ ok: false, error: err.message }` on failure

3. Keep all the existing metadata collection, log reading, and config masking logic unchanged.

**Verify:** Submit feedback → email arrives at linyujade@163.com with screenshots and logs attached.

---

## R13: Simplify Feedback Dialog

**File:** `workspace/chat-ui/ui/src/ui/views/feedback-dialog.ts`

**Description:** Simplify the feedback panel to show only the new-thread form, removing the sidebar navigation and thread detail view.

**Changes:**
1. In `renderFeedbackPanel`, replace the layout:
   - Remove `renderSidebarNav` call
   - Remove conditional rendering (detail/new/empty views)
   - Just show `renderNewContent` directly
   - Add class `feedback-layout--simple` to the container div

2. In `renderNewContent`, change the title from `t("feedback.newThread")` to `t("feedback.title")` with flex layout styling.

**Verify:** Feedback panel shows a simple form without sidebar.

---

## R14: Feedback Submit/Back Returns to Chat

**File:** `workspace/chat-ui/ui/src/ui/app-render.ts`

**Description:** After feedback submit or clicking "back", return to the chat view instead of the feedback thread list.

**Changes:**
1. In `onBackToList` callback: replace the thread-seen-marking and view-switching logic with:
```typescript
state.settings.packclawView = "chat";
state.requestUpdate();
```

2. In the submit success handler: instead of navigating to thread detail or list, reset feedback state and go back to chat:
```typescript
feedbackPanelState = { ...feedbackPanelState, newSubmitting: false, newContent: "", newScreenshots: [], newScreenshotPreviews: [], newFileNames: [], newEmail: "", newIncludeLogs: true };
showToast(state, t("feedback.success"));
state.settings.packclawView = "chat";
state.requestUpdate();
```

**Verify:** Submit feedback → toast shown → returns to chat. Back button → returns to chat.

---

## R15: Auto-Updater Error Localization

**File:** `workspace/src/auto-updater.ts`

**Description:** Translate auto-updater error messages to Chinese. Add a `manualErrorHandled` flag to prevent double error dialogs on manual check.

**Changes:**
1. Add `translateUpdateError(err)` function that maps error patterns to Chinese messages:
   - `ERR_UPDATER_CHANNEL_FILE_NOT_FOUND` / 404 → "暂无可用更新，更新服务正在部署中"
   - `net::ERR_CONNECTION` / `ECONNREFUSED` / `ETIMEDOUT` → "网络连接失败"
   - `ERR_UPDATER_INVALID_VERSION` → "更新信息格式异常"
   - `ERR_CHECKSUM_MISMATCH` → "更新文件校验失败"
   - `ERR_UPDATER_NO_CHECKSUM` → "更新文件信息不完整"
   - Default: original error message

2. Add `let manualErrorHandled = false;` flag.

3. In the "update available" dialog: change title from `"No Updates"` to `"检查更新"`.

4. In both error handlers (autoUpdater.on('error') and checkForUpdates catch):
   - Check `!manualErrorHandled` before showing dialog
   - Set `manualErrorHandled = true`
   - Use `translateUpdateError(err)` as message
   - Change title from `"Update Error"` to `"检查更新失败"`

5. Reset `manualErrorHandled = false` at the start of `checkForUpdates()`.

**Verify:** Manual update check shows Chinese error messages. No double dialog.

---

## R16: Add nodemailer Dependency & watch:chat Script

**File:** `workspace/package.json`

**Description:** Add nodemailer as a production dependency for feedback email. Add @types/nodemailer as dev dependency. Add a `watch:chat` script for development.

**Changes:**
1. In `scripts`, add after `build:chat`:
```json
"watch:chat": "cd chat-ui/ui && npx vite build --watch",
```

2. In `dependencies`, add:
```json
"nodemailer": "^8.0.10"
```

3. In `devDependencies`, add:
```json
"@types/nodemailer": "^8.0.0"
```

**Verify:** `npm install` succeeds. `npm run watch:chat` works.

---

## R17: @aws-sdk Registry Override

**File:** `workspace/scripts/package-resources.js`

**Description:** Add `@aws-sdk:registry=https://registry.npmjs.org` to the generated `.npmrc` file. This is needed because npmmirror's @aws-sdk packages are out of sync.

**Changes:** In the section that writes `.npmrc` content (the array that generates `registry=https://registry.npmmirror.com`), add after the `disturl` line:
```
"@aws-sdk:registry=https://registry.npmjs.org",
```

**Verify:** After `npm run package:resources`, the gateway's `.npmrc` contains the @aws-sdk override.

---

## R18: Fix macOS Parallel Build Missing x64 Target

**File:** `workspace/scripts/dist-all-parallel.sh`

**Description:** The macOS build line only ran `dist:mac:arm64` as a standalone background task, but the script comment says "arm64 → x64 串行". The Windows line correctly uses `( dist:win:x64 && dist:win:arm64 ) &` for serial execution. macOS needs the same pattern to build both architectures.

**Changes:**
```bash
# Before:
run_task "dist:mac:arm64" &

# After:
( run_task "dist:mac:arm64" && run_task "dist:mac:x64" ) &
```

**Verify:** `npm run dist:all:parallel` produces all 4 output directories (`darwin-arm64`, `darwin-x64`, `win32-x64`, `win32-arm64`).

---

## R19: ASAR Stamp Backup + Global Fast-Path for package-resources

**File:** `workspace/scripts/package-resources.js`

**Description:** Two problems cause repeated full rebuilds:
1. ASAR mode deletes `gateway/` directory after packing, which also deletes `.gateway-stamp`. Next build has no stamp → full `npm install openclaw` every time (~2-3 min).
2. Even when individual steps have caches, the script still runs through all steps sequentially (version check, stamp reads, etc.) adding ~10-20s overhead.

Three patches address this:

**Change 1: `readGatewayStamp()` fallback to backup**
```javascript
// Before:
function readGatewayStamp(stampPath) {
  try {
    return fs.readFileSync(stampPath, "utf-8").trim();
  } catch {
    return "";
  }
}

// After:
function readGatewayStamp(stampPath) {
  try {
    return fs.readFileSync(stampPath, "utf-8").trim();
  } catch {
    const backupPath = path.join(path.dirname(path.dirname(stampPath)), ".gateway-stamp.bak");
    try {
      return fs.readFileSync(backupPath, "utf-8").trim();
    } catch {
      return "";
    }
  }
}
```

**Change 2: Backup stamp before deleting `gateway/` in `packGatewayAsar()`**
```javascript
// Insert before "rmDir(gatewayDir)":
const stampPath = path.join(gatewayDir, ".gateway-stamp");
const stampBackup = path.join(targetBase, ".gateway-stamp.bak");
if (fs.existsSync(stampPath)) {
  fs.copyFileSync(stampPath, stampBackup);
}
```

**Change 3: Add `canSkipAll()` function + early return in `main()`**

New function `canSkipAll(opts, targetPaths)` checks:
- Runtime `.node-stamp` exists
- Gateway stamp matches current platform/arch/source (via `readGatewayStamp` with backup fallback)
- ASAR file exists (if ASAR mode) or `entry.js` exists (if non-ASAR)
- App icon exists
- OfficeCLI stamp and binary exist (if pinned in package.json)

If all pass, `main()` prints "所有资源已就绪（缓存全部命中），跳过打包" and returns immediately after `verifyOutput()`.

**Verify:** Run `npm run package:resources` twice. Second run should complete in <2 seconds with "缓存全部命中" message.

---

## R20: Remove Moonshot Provider Label

**File:** `workspace/chat-ui/ui/src/ui/views/setup/setup-constants.ts`

**Description:** Remove `moonshot` from `getProviderLabels()`. PackClaw uses 51key as default provider and doesn't need moonshot in the label map (it's not in `PROVIDER_DISPLAY_ORDER` either).

**Changes:** Delete the line:
```typescript
    moonshot: t("setup.provider.label.moonshot"),
```

**Verify:** `tsc --noEmit` passes. No moonshot label in setup constants.

---

## R21: Add "ready-to-install" Status to Update Banner State Machine

**File:** `workspace/src/update-banner-state.ts`

**Description:** Add a new update status `"ready-to-install"` and event type `"download-ready"` to the state machine. On macOS, after downloading and extracting the update zip, the status transitions to `"ready-to-install"` instead of immediately restarting. The user clicks "open installer" to trigger the actual install.

**Changes:**
1. Expand `UpdateBannerStatus` type:
```typescript
export type UpdateBannerStatus = "hidden" | "available" | "downloading" | "ready-to-install";
```

2. Add `download-ready` event type:
```typescript
| { type: "download-ready" };
```

3. In `reduceUpdateBannerState`, add explicit `update-not-available` case (no longer falls through):
```typescript
case "update-not-available":
  return createInitialUpdateBannerState();
```

4. Add `download-ready` case in reducer:
```typescript
case "download-ready":
  if (!state.version) {
    return createInitialUpdateBannerState();
  }
  return {
    status: "ready-to-install",
    version: state.version,
    percent: null,
    showBadge: true,
  };
```

**Verify:** `tsc --noEmit` passes. State machine accepts "download-ready" event.

---

## R22: macOS Manual Installer: Extract ZIP Instead of Auto-Restart

**File:** `workspace/src/auto-updater.ts`

**Description:** On macOS, the upstream `quitAndInstall()` approach doesn't work well (DMG-based updates fail to restart properly). Instead, after downloading the update zip, extract it to find the `.app` bundle and store the path in `pendingUpdateFile`. When the user clicks "open installer", copy the `.app` to `/Applications` and restart via `app.relaunch()`. Windows keeps the original `quitAndInstall()` behavior.

**Changes:**
1. Expand imports:
```typescript
import { app, dialog, shell } from "electron";
import * as child_process from "child_process";
import * as fs from "fs";
import * as path from "path";
```

2. Add state variable after `downloadInFlight`:
```typescript
let pendingUpdateFile: string | null = null;
```

3. Replace the `update-downloaded` handler:
   - macOS: Read `update-info.json` from cache dir → extract zip via `unzip` → find `.app` → set `pendingUpdateFile` → emit `download-ready`
   - Windows: Keep `publishUpdateBannerState({ type: "download-finished" })` + `quitAndInstall(false, true)`

4. Add exported `openUpdateInstaller()` function:
   - macOS: `cp -R` pending `.app` to `/Applications` → `app.relaunch()` + `app.exit(0)`
   - Fallback: `shell.openPath(pendingUpdateFile)`

**Verify:** On macOS, update download shows "点击打开安装包" pill. Clicking it copies app to /Applications and restarts.

---

## R23: IPC Plumbing for openUpdateInstaller

**Files:** `workspace/src/main.ts`, `workspace/src/preload.ts`, `workspace/chat-ui/ui/src/ui/data/ipc-bridge.ts`

**Description:** Wire `openUpdateInstaller` through the Electron IPC bridge so the renderer can call it.

**Changes:**
1. `main.ts`: Import `openUpdateInstaller` from auto-updater. Add IPC handler:
```typescript
ipcMain.handle("app:open-update-installer", () => openUpdateInstaller());
```

2. `preload.ts`: Add bridge method:
```typescript
openUpdateInstaller: () => ipcRenderer.invoke("app:open-update-installer"),
```
Also update status type in `onUpdateState` callback to include `"ready-to-install"`.

3. `ipc-bridge.ts`: Update `UpdateState.status` type, add to `PackClawBridgeExtended` interface, add exported function:
```typescript
export function openUpdateInstaller(): Promise<void> {
  return oc().openUpdateInstaller() as Promise<void>;
}
```

**Verify:** `tsc --noEmit` passes. Renderer can call `openUpdateInstaller()` without type errors.

---

## R24: Sidebar Ready-to-Install UI

**Files:** `workspace/chat-ui/ui/src/ui/sidebar.ts`, `workspace/chat-ui/ui/src/styles.css`, `workspace/chat-ui/ui/src/ui/app-render.ts`, `workspace/chat-ui/ui/src/ui/app.ts`

**Description:** When update status is `"ready-to-install"`, the sidebar pill shows "点击打开安装包" with a download icon, and a "手动下载" link below. Clicking the pill calls `openUpdateInstaller` instead of `applyUpdate`.

**Changes:**
1. `app.ts`: Update `PackClawUpdateState` status type and `applyUpdateBannerState` validator to accept `"ready-to-install"`.

2. `sidebar.ts`:
   - Update `SidebarProps` types: `updateStatus` union + add `onOpenUpdateInstaller`
   - Update label: `ready-to-install` → `t("sidebar.updateReadyToInstall")`, else → `t("sidebar.updateReady")`
   - Button click: `ready-to-install` → `onOpenUpdateInstaller`, else → `onApplyUpdate`
   - Icon: `ready-to-install` → `icons.download`, else → `icons.zap`
   - Add manual download `<a>` link after button when `ready-to-install`

3. `styles.css`: Add `.packclaw-sidebar__manual-dl` styles (centered, small text, hover color change).

4. `app-render.ts`: Add `handleOpenUpdateInstaller` function (same pattern as `handleApplyUpdate` but checks `"ready-to-install"` status and calls `openUpdateInstaller`). Pass `onOpenUpdateInstaller` to sidebar props.

**Verify:** Sidebar shows "点击打开安装包" with download icon after update download. Clicking copies app and restarts.

---

## R25: About Tab Open Installer Button

**File:** `workspace/chat-ui/ui/src/ui/views/settings/tab-about.ts`

**Description:** In the About → Software Update section, when status is `"ready-to-install"`, show the new version number, an "打开安装包" button, and a "手动下载" link.

**Changes:**
After the `downloading` status block, add:
```typescript
${us.status === "ready-to-install" ? html`
  <div style="font-size:13px;margin-bottom:8px">${us.version ?? ""}</div>
  <button class="oc-settings__btn oc-settings__btn--primary" @click=${() => ipc.openUpdateInstaller()}>
    ${t("settings.about.openInstaller")}
  </button>
  <div style="margin-top:8px">
    <a href="https://www.packclaw.cn/#download" target="_blank" rel="noopener" style="color:var(--oc-text-link);font-size:13px">${t("settings.about.manualDownload")}</a>
  </div>
` : nothing}
```

**Verify:** Settings → About → update ready shows "打开安装包" button and "手动下载" link.

---

## R26: i18n Strings for Update Installer Flow

**File:** `workspace/chat-ui/ui/src/ui/i18n.ts`

**Description:** Add Chinese and English i18n strings for the new update installer UI elements.

**Changes:**
1. Chinese (`zh` dict):
```
"sidebar.updateReadyToInstall": "点击打开安装包",
"settings.about.openInstaller": "打开安装包",
"settings.about.manualDownload": "手动下载",
```

2. English (`en` dict):
```
"sidebar.updateReadyToInstall": "Open installer",
"settings.about.openInstaller": "Open Installer",
"settings.about.manualDownload": "Manual Download",
```

**Verify:** Both locales show correct strings in sidebar and about tab.

---

## R27: Disable hardenedRuntime and Notarize in electron-builder.yml

**File:** `workspace/electron-builder.yml`

**Description:** Disable macOS `hardenedRuntime` and `notarize` for development builds. These require valid Apple Developer certificates and notarization credentials which are only available in CI with secrets.

**Changes:**
```yaml
# Before:
  hardenedRuntime: true
  notarize: true

# After:
  hardenedRuntime: false
  notarize: false
```

**Verify:** `npm run dist:mac` completes without code signing errors on dev machines.

---

## R28: Remove CDN Cache Refresh from CI Workflows

**Files:** `workspace/.github/workflows/build-release.yml`, `workspace/.github/workflows/publish-release.yml`

**Description:** Remove the `volcengine-cdn-refresh.js` CDN cache invalidation steps from both CI workflows. TOS CDN cache expires naturally via TTL. This simplifies CI and removes a dependency on the refresh script.

**Changes:**
1. `build-release.yml`: Remove the "刷新 dev 通道 CDN 缓存" step entirely. Update the comment on the "移除 dev yml" step to reflect that CDN refresh is no longer done.

2. `publish-release.yml`: Remove the "刷新 CDN 缓存" step entirely.

**Verify:** CI workflows no longer reference `volcengine-cdn-refresh.js`. Updates still propagate via CDN TTL expiry.

---

## Overlay Files (New Files — No Patching Needed)

These files are already in `overlay/` and copied via `rsync`:

| File | Purpose |
|------|---------|
| `overlay/chat-ui/ui/src/ui/views/setup/provider-51key-config.ts` | 51key provider definition, API endpoints |
| `overlay/chat-ui/ui/src/ui/views/setup/setup-51key-section.ts` | 51key setup wizard (email login, verify code, balance) |
| `overlay/chat-ui/ui/src/ui/views/settings/settings-51key-section.ts` | 51key settings section (login, balance, model select) |
| `overlay/chat-ui/ui/src/ui/chat/chat-51key-balance.ts` | 51key balance check + empty response rendering |
| `overlay/chat-ui/ui/src/ui/i18n-51key.ts` | 51key i18n strings (zh + en) |
| `overlay/scripts/dist-all-parallel.sh` | Parallel build script for 4 targets |
| `overlay/assets/*` | Custom app icons (icon.png, icon.icns, icon.ico, tray icons) |
