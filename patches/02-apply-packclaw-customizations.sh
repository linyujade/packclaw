#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 02-apply-packclaw-customizations.sh
#
# Applies all PackClaw customizations to workspace/ after upstream sync + rebrand.
# Run AFTER: 01-rebrand-oneclaw-to-packclaw.sh
# Run BEFORE: npm install && npm run build
#
# Each section is labeled R01–R17. See patches/REQUIREMENTS.md for full details.
# If a patch fails, the script warns but continues. Check FAILURES at the end.
#
# Strategy:
#   - Simple line changes   → sed
#   - Multi-line changes     → perl -0777 (slurp mode)
#   - Complex structural     → node.js inline scripts (heredoc)
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"
FAILURES=""

warn() { echo "  ⚠ [FAIL] $1"; FAILURES="$FAILURES\n  $1"; }
ok()   { echo "  ✓ $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# R01: 51key Provider Preset in Backend
# File: src/provider-config.ts
# Desc: Add 51key preset (baseUrl + api type) and a no-op verify case
#       so the backend recognizes "51key" as a valid provider.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R01] Patching src/provider-config.ts ..."
FILE="$WS/src/provider-config.ts"
if [ -f "$FILE" ] && ! grep -q '"51key"' "$FILE"; then
  perl -0777 -pi -e \
    's/(google: \{ baseUrl: "[^"]+", api: "[^"]+" \},)/$1\n  "51key": { baseUrl: "https:\/\/api.lmdone.com\/v1", api: "openai-completions" },/' \
    "$FILE"
  perl -0777 -pi -e \
    's/(case "google":\n\s+await verifyGoogle\([^)]+\);\n\s+break;)/$1\n      case "51key":\n        break;/' \
    "$FILE"
  grep -q '"51key"' "$FILE" && ok "R01" || warn "R01: 51key preset not found after patch"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R02: 51key in Setup Constants
# File: chat-ui/ui/src/ui/views/setup/setup-constants.ts
# Desc: Import 51key config, add to PROVIDERS map, set as first/default provider,
#       add i18n labels for 51key and moonshot in getProviderLabels().
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R02] Patching setup-constants.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/setup/setup-constants.ts"
if [ -f "$FILE" ] && ! grep -q 'PROVIDER_51KEY' "$FILE"; then
  # Add import after existing imports
  perl -0777 -pi -e \
    's/(import \{ t \} from "..\/..\/i18n\.ts";)/$1\nimport { PROVIDER_51KEY, KEY_51KEY_LOCAL_STATE, API_51KEY } from ".\/provider-51key-config.ts";\n\nexport { KEY_51KEY_LOCAL_STATE, API_51KEY };/' \
    "$FILE"
  # Add 51key to PROVIDERS map (before "custom")
  perl -0777 -pi -e \
    's/(  custom: \{\n    placeholder: "",\n    models: \[\],\n  \},)/  "51key": PROVIDER_51KEY,\n$1/' \
    "$FILE"
  # Change PROVIDER_DISPLAY_ORDER: put 51key first, remove moonshot
  perl -pi -e \
    's/PROVIDER_DISPLAY_ORDER = \["moonshot", "anthropic", "openai", "google", "custom"\]/PROVIDER_DISPLAY_ORDER = ["51key", "anthropic", "openai", "google", "custom"]/' \
    "$FILE"
  # Add 51key + moonshot labels in getProviderLabels
  perl -0777 -pi -e \
    's/(    google: t\("setup\.provider\.label\.google"\),)/$1\n    "51key": t("setup.provider.label.51key"),\n    moonshot: t("setup.provider.label.moonshot"),/' \
    "$FILE"
  grep -q 'PROVIDER_51KEY' "$FILE" && ok "R02" || warn "R02: setup-constants.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R03: 51key Setup Wizard Section
# File: chat-ui/ui/src/ui/views/setup/setup-step2-provider.ts
# Desc: Make 51key default provider in setup. When selected, show the 51key
#       login section instead of standard API key form. Add verify-and-continue
#       button for 51key.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R03] Patching setup-step2-provider.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/setup/setup-step2-provider.ts"
if [ -f "$FILE" ] && ! grep -q 'init51keyDefaults' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add 51key imports after setup-constants import
c = c.replace(
  `} from "./setup-constants.ts";`,
  `} from "./setup-constants.ts";
import {
  init51keyDefaults, ensure51keyStateLoaded, handle51keyProviderChange,
  handle51keyVerifyAndContinue, render51keySection,
} from "./setup-51key-section.ts";`
);

// 2. Change default provider to "51key"
c = c.replace(
  `currentProvider: "moonshot",`,
  `currentProvider: "51key",`
);

// 3. Add modelAlias field after customModelId
c = c.replace(
  `customModelId: "",\n  baseUrl: "",`,
  `customModelId: "",\n  modelAlias: "",\n  baseUrl: "",`
);

// 4. Spread init51keyDefaults() into state
c = c.replace(
  `error: null as string | null,\n};`,
  `error: null as string | null,\n  ...init51keyDefaults(),\n};`
);

// 5. In onProviderChange: add 51key branch, wrap auto-select in else
c = c.replace(
  `  if (provider === "moonshot") {\n    s.subPlatform = "kimi-code";\n  }\n  // Auto-select first model\n  const models = getModels();\n  if (models.length) s.modelId = models[0];\n  state.requestUpdate();\n}`,
  `  if (provider === "moonshot") {\n    s.subPlatform = "kimi-code";\n  }\n  if (provider === "51key") {\n    handle51keyProviderChange(s, state);\n  } else {\n    const models = getModels();\n    if (models.length) s.modelId = models[0];\n  }\n  state.requestUpdate();\n}`
);

// 6. In renderStep2: add ensure51keyStateLoaded and is51key const
c = c.replace(
  `export function renderStep2(state: AppViewState, goToStep: (step: number) => void) {\n  const models = getModels();`,
  `export function renderStep2(state: AppViewState, goToStep: (step: number) => void) {\n  if (s.currentProvider === "51key") ensure51keyStateLoaded(s);\n  const models = getModels();`
);

c = c.replace(
  `const isManualCustom = isCustom && !s.customPreset;\n\n  // Ensure modelId has a value`,
  `const isManualCustom = isCustom && !s.customPreset;\n  const is51key = s.currentProvider === "51key";\n\n  // Ensure modelId has a value`
);

// 7. Wrap provider form: add 51key conditional after provider segment
c = c.replace(
  `      ></oc-provider-segment>\n\n      \${s.currentProvider === "moonshot"`,
  `      ></oc-provider-segment>\n\n      \${is51key ? render51keySection(s, state) : html\`\n      \${s.currentProvider === "moonshot"`
);

// 8. Change error message box: hide when 51key has retrieved key
c = c.replace(
  `      <oc-message-box .message=\${s.error ?? ""} .type=\${"error"} .visible=\${!!s.error}></oc-message-box>`,
  `    \${!s["51keyApiKeyRetrieved"] ? html\`<oc-message-box .message=\${s.error ?? ""} .type=\${"error"} .visible=\${!!s.error}></oc-message-box>\` : nothing}`
);

// 9. Close 51key wrapper before step-body closing div
c = c.replace(
  `      \` : nothing}\n      </div>\n\n      <div class="oc-setup-btn-row">`,
  `      \` : nothing}\n      \`}\n      </div>\n\n      <div class="oc-setup-btn-row">`
);

// 10. Change verify button: exclude 51key, add 51key verify button
c = c.replace(
  `\${!isOAuth ? html\`\n          <button class="oc-setup-btn oc-setup-btn--primary" ?disabled=\${s.verifying}\n            @click=\${() => handleVerify(state, goToStep)}>\n            \${s.verifying ? "..." : t("setup.provider.verify")}\n          </button>\n        \` : nothing}`,
  `\${!isOAuth && !is51key ? html\`\n          <button class="oc-setup-btn oc-setup-btn--primary" ?disabled=\${s.verifying}\n            @click=\${() => handleVerify(state, goToStep)}>\n            \${s.verifying ? "..." : t("setup.provider.verify")}\n          </button>\n        \` : nothing}\n        \${is51key && s["51keyApiKeyRetrieved"] ? html\`\n          <button class="oc-setup-btn oc-setup-btn--primary" ?disabled=\${s.verifying}\n            @click=\${() => handle51keyVerifyAndContinue(s, state, goToStep)}>\n            \${s.verifying ? "..." : t("setup.provider.51key.verifyAndContinue")}\n          </button>\n        \` : nothing}`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'init51keyDefaults' "$FILE" && ok "R03" || warn "R03: setup-step2-provider.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R04: 51key Settings Provider Tab
# File: chat-ui/ui/src/ui/views/settings/tab-provider.ts
# Desc: When user selects 51key in settings, show the 51key login/balance
#       section instead of standard provider form.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R04] Patching tab-provider.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-provider.ts"
if [ -f "$FILE" ] && ! grep -q 'init51keyDefaults' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add 51key imports
c = c.replace(
  `} from "../setup/setup-constants.ts";`,
  `} from "../setup/setup-constants.ts";
import { init51keyDefaults, load51keyState, handle51keyProviderChange } from "../setup/setup-51key-section.ts";
import { render51keySettingsSection } from "./settings-51key-section.ts";`
);

// 2. Change default provider
c = c.replace(
  `currentProvider: "moonshot",`,
  `currentProvider: "51key",`
);

// 3. Add init51keyDefaults to state
c = c.replace(
  `lockedProvider: null as string | null,\n    initialized: false,\n  };`,
  `lockedProvider: null as string | null,\n    initialized: false,\n    ...init51keyDefaults(),\n  };`
);

// 4. Add 51key loading in init function (after models assignment)
c = c.replace(
  `    if (models) s.configuredModels = models;\n    if (isKimiCodeProvider()) await checkOAuthStatus(state);`,
  `    if (models) s.configuredModels = models;\n    if (s.currentProvider === "51key") {\n      load51keyState(s);\n      if (!s.modelId) {\n        const m = PROVIDERS["51key"]?.models ?? [];\n        if (m.length) s.modelId = m[0];\n      }\n    }\n    if (isKimiCodeProvider()) await checkOAuthStatus(state);`
);

// 5. Add 51key branch in onProviderChange
c = c.replace(
  `  if (provider === "moonshot") s.subPlatform = "kimi-code";\n  const models = getModels();\n  if (models.length) s.modelId = models[0];\n  // Fill from saved\n  const saved = lookupSavedProvider(provider);\n  fillSavedProviderFields(saved);`,
  `  if (provider === "moonshot") s.subPlatform = "kimi-code";\n  if (provider === "51key") {\n    handle51keyProviderChange(s, state);\n  } else {\n    const models = getModels();\n    if (models.length) s.modelId = models[0];\n    const saved = lookupSavedProvider(provider);\n    fillSavedProviderFields(saved);\n  }`
);

// 6. Wrap settings form with 51key conditional
// Find the provider segment and add conditional after it
c = c.replace(
  `          ></oc-provider-segment>\n\n          \${s.currentProvider === "moonshot"`,
  `          ></oc-provider-segment>\n\n          \${s.currentProvider === "51key" ? render51keySettingsSection(s, state, () => handleSave(state), getSaveButtonLabel, onModelSelectChange) : html\`\n          \${s.currentProvider === "moonshot"`
);

// Find the save button row and close the conditional after it
c = c.replace(
  /\${getSaveButtonLabel\(\)}\s*<\/button>\s*<\/div>(\s*<\/div>\s*<\/div>\s*<\/div>)/,
  `\${getSaveButtonLabel()}\n            </button>\n          </div>\n          \`}\n        </div>\n      </div>\n    </div>`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'init51keyDefaults' "$FILE" && ok "R04" || warn "R04: tab-provider.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R05: 51key Empty Response Balance Check
# File: chat-ui/ui/src/ui/chat/grouped-render.ts
# Desc: When 51key returns empty response (balance depleted), show a balance
#       check message with recharge link instead of nothing.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R05] Patching grouped-render.ts ..."
FILE="$WS/chat-ui/ui/src/ui/chat/grouped-render.ts"
if [ -f "$FILE" ] && ! grep -q 'render51keyEmptyResponse' "$FILE"; then
  # Add import
  perl -0777 -pi -e \
    's/(import \{ extractToolCards, renderToolCardSidebar \} from "\.\/tool-cards\.ts";)/$1\nimport { render51keyEmptyResponse } from ".\/chat-51key-balance.ts";/' \
    "$FILE"
  # Add empty response handling before `return nothing`
  perl -0777 -pi -e \
    's/(if \(!markdown && !hasToolCards && !hasImages\) \{\n)/$1    const empty51key = render51keyEmptyResponse(m, bubbleClasses);\n    if (empty51key) return empty51key;\n/' \
    "$FILE"
  grep -q 'render51keyEmptyResponse' "$FILE" && ok "R05" || warn "R05: grouped-render.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R06: 51key i18n Integration
# File: chat-ui/ui/src/ui/i18n.ts
# Desc: Import and merge 51key i18n dictionary. Update channels description
#       to remove "Kimi" mention.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R06] Patching i18n.ts ..."
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && ! grep -q 'i18n51key' "$FILE"; then
  # Add import at top
  perl -0777 -pi -e \
    's/( \*\/\n\n)(export type Locale)/$1import { i18n51key } from ".\/i18n-51key.ts";\n\n$2/' \
    "$FILE"
  # Update zh channels desc: remove Kimi
  perl -pi -e \
    's/连接微信、飞书、企业微信、钉钉、Kimi 或 QQ/连接微信、飞书、企业微信、钉钉 或 QQ/g' \
    "$FILE"
  # Add merge code after dict closing };
  perl -0777 -pi -e \
    's/(\n};\n\nlet currentLocale)/\n};\n\n\/\/ Merge 51key i18n plugin into main dict\nfor (const locale of Object.keys(i18n51key) as Locale[]) {\n  Object.assign(dict[locale], i18n51key[locale]);\n}\n\nlet currentLocale/' \
    "$FILE"
  grep -q 'i18n51key' "$FILE" && ok "R06" || warn "R06: i18n.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R07: Disable KimiClaw Channel & Remove Search Tab
# File: chat-ui/ui/src/ui/views/settings/settings-constants.ts
# Desc: Comment out kimiclaw channel. Remove "search" tab from settings nav.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R07] Patching settings-constants.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/settings-constants.ts"
if [ -f "$FILE" ]; then
  # Comment out kimiclaw channel
  sed -i '' 's/^  { id: "kimiclaw",/  \/\/ { id: "kimiclaw",/' "$FILE"
  sed -i '' 's/^    labelKey: "settings.channels.kimiclaw",/    \/\/ labelKey: "settings.channels.kimiclaw",/' "$FILE"
  sed -i '' 's/^    descKey: "settings.channels.kimiclaw.desc" },/    \/\/ descKey: "settings.channels.kimiclaw.desc" },/' "$FILE"
  # Remove search tab
  sed -i '' '/{ id: "search", labelKey: "settings.nav.search" },/d' "$FILE"
  ok "R07"
else
  warn "R07: settings-constants.ts not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R08: Remove Webbridge Radio Option
# File: chat-ui/ui/src/ui/views/settings/tab-advanced.ts
# Desc: Remove the "webbridge" radio button from browser profile section.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R08] Patching tab-advanced.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-advanced.ts"
if [ -f "$FILE" ] && grep -q 'value="webbridge"' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");
c = c.replace(
  /\n\s*<label class="oc-settings__radio">\s*<input[\s\S]*?value="webbridge"[\s\S]*?<\/label>\n(\s*<label)/,
  "\n$1"
);
fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  ! grep -q 'value="webbridge"' "$FILE" && ok "R08" || warn "R08: webbridge removal failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R09: Remove Kimi Embedding Toggle
# File: chat-ui/ui/src/ui/views/settings/tab-memory.ts
# Desc: Remove embedding toggle and isKimiCodeConfigured state, which depend
#       on Kimi (disabled in PackClaw).
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R09] Patching tab-memory.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/settings/tab-memory.ts"
if [ -f "$FILE" ] && grep -q 'embeddingEnabled' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Remove from state
c = c.replace(/    embeddingEnabled: false,\n    isKimiCodeConfigured: false,\n/, "");

// 2. Remove from init
c = c.replace(/    s\.embeddingEnabled = config\.embeddingEnabled \?\? false;\n    s\.isKimiCodeConfigured = config\.isKimiCodeConfigured \?\? false;\n/, "");

// 3. Remove from save
c = c.replace(/, embeddingEnabled: s\.embeddingEnabled/, "");

// 4. Remove embeddingStatus variable
c = c.replace(/\n  const embeddingStatus = s\.isKimiCodeConfigured && s\.embeddingEnabled\n    \? t\("settings\.memory\.embeddingEnabled"\)\n    : !s\.isKimiCodeConfigured\n      \? t\("settings\.memory\.embeddingRequiresKimi"\)\n      : "";\n/, "\n");

// 5. Remove embedding toggle block
c = c.replace(/\n      <div class="oc-settings__form-group">\n        <oc-toggle-switch .label=\$\{t\("settings\.memory\.embedding"\)\} \.checked=\$\{s\.embeddingEnabled\}\n          \.disabled=\$\{!s\.isKimiCodeConfigured\}\n          @change=\$\{\(e: CustomEvent\) => \{ s\.embeddingEnabled = e\.detail\.checked; state\.requestUpdate\(\); \}\}\n        ><\/oc-toggle-switch>\n        \$\{embeddingStatus \? html\`<div class="oc-settings__field-hint">\$\{embeddingStatus\}<\/div>\` : ""\}\n      <\/div>\n/, "\n");

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  ! grep -q 'embeddingEnabled' "$FILE" && ok "R09" || warn "R09: tab-memory.ts patch incomplete"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R10: Auto-Disable KimiClaw Plugin on Startup
# File: src/main.ts
# Desc: Add migration function that disables kimi-claw plugin on every startup
#       to prevent background API usage. Called in both "oneclaw" and
#       "legacy-oneclaw" startup paths.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R10] Patching main.ts ..."
FILE="$WS/src/main.ts"
if [ -f "$FILE" ] && ! grep -q 'migrateDisableKimiClaw' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add migrateDisableKimiClaw function after migrateKimiPluginDeviceId
c = c.replace(
  `function migrateKimiPluginDeviceId(): void {
  try {
    const config = readUserConfig();
    if (!ensureKimiPluginDeviceId(config)) return;
    writeUserConfig(config);
    log.info("[migrate] 已为 kimi-claw.config.bridge 补齐 deviceId");
  } catch {
    // 迁移失败不阻塞启动
  }
}`,
  `function migrateKimiPluginDeviceId(): void {
  try {
    const config = readUserConfig();
    if (!ensureKimiPluginDeviceId(config)) return;
    writeUserConfig(config);
    log.info("[migrate] 已为 kimi-claw.config.bridge 补齐 deviceId");
  } catch {
    // 迁移失败不阻塞启动
  }
}

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
}`
);

// 2. Add call in "oneclaw" (normal startup) path
c = c.replace(
  `      migrateKimiPluginDeviceId();\n      void reconcileCliOnAppLaunch().catch((err) => {\n        log.error(\`[migrate] CLI launch reconciliation failed: \${err instanceof Error ? err.message : String(err)}\`);\n      });\n      await startGatewayAndShowMain("app:startup");`,
  `      migrateKimiPluginDeviceId();\n      migrateDisableKimiClaw();\n      void reconcileCliOnAppLaunch().catch((err) => {\n        log.error(\`[migrate] CLI launch reconciliation failed: \${err instanceof Error ? err.message : String(err)}\`);\n      });\n      await startGatewayAndShowMain("app:startup");`
);

// 3. Add call in "legacy-oneclaw" path
c = c.replace(
  `      migrateKimiPluginDeviceId();\n      void reconcileCliOnAppLaunch().catch((err) => {\n        log.error(\`[migrate] CLI launch reconciliation failed: \${err instanceof Error ? err.message : String(err)}\`);\n      });\n      await startGatewayAndShowMain("app:startup:legacy-migrate");`,
  `      migrateKimiPluginDeviceId();\n      migrateDisableKimiClaw();\n      void reconcileCliOnAppLaunch().catch((err) => {\n        log.error(\`[migrate] CLI launch reconciliation failed: \${err instanceof Error ? err.message : String(err)}\`);\n      });\n      await startGatewayAndShowMain("app:startup:legacy-migrate");`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'migrateDisableKimiClaw' "$FILE" && ok "R10" || warn "R10: main.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R11: Update Channels Description (Settings JS)
# File: settings/settings.js
# Desc: Remove "Kimi" from channel descriptions in both English and Chinese.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R11] Patching settings.js ..."
FILE="$WS/settings/settings.js"
if [ -f "$FILE" ]; then
  # English: remove ", Kimi"
  sed -i '' 's/WeCom, DingTalk, Kimi, or QQ/WeCom, DingTalk, or QQ/g' "$FILE"
  # Chinese: remove "、Kimi"
  sed -i '' 's/钉钉、Kimi 或 QQ/钉钉 或 QQ/g' "$FILE"
  ok "R11"
else
  warn "R11: settings.js not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R12: Feedback Submission via SMTP Email
# File: src/feedback-ipc.ts
# Desc: Replace upstream multipart HTTP + SSE submission with nodemailer SMTP.
#       Feedback sent to linyujade@163.com via smtp.163.com:465.
#       Keeps metadata collection, log reading, config masking unchanged.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R12] Patching feedback-ipc.ts ..."
FILE="$WS/src/feedback-ipc.ts"
if [ -f "$FILE" ] && ! grep -q 'nodemailer' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add nodemailer import
c = c.replace(
  `import * as https from "https";`,
  `import * as https from "https";\nimport * as nodemailer from "nodemailer";`
);

// 2. Replace the entire submission block: from metadata stringify to return result
c = c.replace(
  /    const metadata = JSON\.stringify\(metadataObj\);\n\n    \/\/ 构造 multipart body[\s\S]*?    return result;\n  \}\);/,
  `    const metadata = JSON.stringify(metadataObj, null, 2);

    const htmlBody = \`
      <h2>PackClaw 用户反馈</h2>
      <p><strong>反馈内容：</strong></p>
      <pre style="white-space:pre-wrap;background:#f5f5f5;padding:12px;border-radius:6px;">\${content.replace(/</g, "&lt;").replace(/>/g, "&gt;")}</pre>
      \${email ? \`<p><strong>用户邮箱：</strong>\${email.replace(/</g, "&lt;")}</p>\` : ""}
      <p><strong>设备信息：</strong></p>
      <pre style="white-space:pre-wrap;background:#f5f5f5;padding:12px;border-radius:6px;font-size:12px;">\${metadata.replace(/</g, "&lt;").replace(/>/g, "&gt;")}</pre>
    \`;

    const attachments = [];

    for (let i = 0; i < screenshots.length; i++) {
      const buf = Buffer.from(screenshots[i], "base64");
      const fileName = fileNames?.[i] || \`screenshot-\${i + 1}.png\`;
      attachments.push({ filename: fileName, content: buf });
    }

    if (includeLogs) {
      const stateDir = resolveUserStateDir();
      const sensitiveRe = /key=|token=|secret=|password=|authorization:|"apiKey"|"api_key"|"apikey"|bearer |sk-[a-zA-Z0-9]{8}/i;
      const MAX_LOG_SIZE = 10 * 1024 * 1024;
      for (const name of ["app.log", "gateway.log"]) {
        const logPath = path.join(stateDir, name);
        try {
          if (!fs.existsSync(logPath)) continue;
          const stat = fs.statSync(logPath);
          let raw;
          if (stat.size <= MAX_LOG_SIZE) {
            raw = fs.readFileSync(logPath, "utf-8");
          } else {
            const fd = fs.openSync(logPath, "r");
            const buf = Buffer.alloc(MAX_LOG_SIZE);
            fs.readSync(fd, buf, 0, MAX_LOG_SIZE, stat.size - MAX_LOG_SIZE);
            fs.closeSync(fd);
            raw = buf.toString("utf-8");
            const firstNewline = raw.indexOf("\\n");
            if (firstNewline > 0) raw = raw.slice(firstNewline + 1);
          }
          const lines = raw.split("\\n").filter((l) => !sensitiveRe.test(l));
          attachments.push({ filename: name, content: lines.join("\\n") });
        } catch {}
      }
    }

    const stateDir2 = resolveUserStateDir();
    try {
      const configPath = path.join(stateDir2, "openclaw.json");
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, "utf-8");
        const parsed = JSON.parse(raw);
        const masked = maskConfigValues(parsed);
        attachments.push({ filename: "openclaw.masked.json", content: JSON.stringify(masked, null, 2) });
      }
    } catch {}
    try {
      const tree = buildStateTree();
      attachments.push({ filename: "state-tree.csv", content: tree });
    } catch {}

    const transporter = nodemailer.createTransport({
      host: "smtp.163.com",
      port: 465,
      secure: true,
      auth: {
        user: "linyujade@163.com",
        pass: "CKVZGjpsVrntzHge",
      },
    });

    log.info(\`反馈提交(邮件): content=\${content.length}字, screenshots=\${screenshots.length}, includeLogs=\${includeLogs}\`);

    try {
      const info = await transporter.sendMail({
        from: '"PackClaw 反馈" <linyujade@163.com>',
        to: "linyujade@163.com",
        subject: \`[PackClaw 反馈] \${content.slice(0, 50).replace(/\\n/g, " ")}\${content.length > 50 ? "..." : ""}\`,
        html: htmlBody,
        attachments,
      });
      log.info(\`反馈邮件发送成功: messageId=\${info.messageId}\`);
      return { ok: true, id: Date.now() };
    } catch (err) {
      log.error(\`反馈邮件发送失败: \${err.message}\`);
      return { ok: false, error: err.message || "邮件发送失败" };
    }
  });`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'nodemailer' "$FILE" && ok "R12" || warn "R12: feedback-ipc.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R13: Simplify Feedback Dialog
# File: chat-ui/ui/src/ui/views/feedback-dialog.ts
# Desc: Remove sidebar navigation and thread detail view. Show only the
#       new-thread form directly. Change title from "newThread" to "title".
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R13] Patching feedback-dialog.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/feedback-dialog.ts"
if [ -f "$FILE" ] && ! grep -q 'feedback-layout--simple' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Simplify renderFeedbackPanel: remove sidebar, just show new content form
c = c.replace(
  `  const selectedId = state.detailThread?.id ?? null;
  return html\`
    <div class="feedback-layout">
      \${renderSidebarNav(state, callbacks, selectedId)}
      <div class="feedback-layout__content">
        \${state.view === "detail"
          ? renderDetailContent(state, callbacks)
          : state.view === "new"
            ? renderNewContent(state, callbacks)
            : renderEmptyContent()}
      </div>
    </div>`,
  `  return html\`
    <div class="feedback-layout feedback-layout--simple">
      <div class="feedback-layout__content">
        \${renderNewContent(state, callbacks)}
      </div>
    </div>`
);

// 2. Change title in renderNewContent
c = c.replace(
  `      <h2 class="feedback-layout__content-title">\${t("feedback.newThread")}</h2>`,
  `      <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">\n        <h2 class="feedback-layout__content-title" style="margin:0">\${t("feedback.title")}</h2>\n      </div>`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'feedback-layout--simple' "$FILE" && ok "R13" || warn "R13: feedback-dialog.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R14: Feedback Submit/Back Returns to Chat
# File: chat-ui/ui/src/ui/app-render.ts
# Desc: After feedback submit or clicking "back", return to chat view instead
#       of thread list. Reset feedback state after successful submit.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R14] Patching app-render.ts ..."
FILE="$WS/chat-ui/ui/src/ui/app-render.ts"
if [ -f "$FILE" ] && grep -q 'onBackToList' "$FILE" && ! grep -q 'packclawView = "chat"' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Simplify onBackToList: just go back to chat
c = c.replace(
  /    onBackToList: \(\) => \{[\s\S]*?loadFeedbackThreads\(state\);\n    \},/,
  `    onBackToList: () => {\n      state.settings.packclawView = "chat";\n      state.requestUpdate();\n    },`
);

// 2. Simplify submit success handler
c = c.replace(
  /        if \(result\?\.ok\) \{\n          feedbackPanelState = \{ \.\.\.feedbackPanelState, newSubmitting: false \};\n          showToast\(state, t\("feedback\.success"\)\);[\s\S]*?\n        \} else \{/,
  `        if (result?.ok) {\n          feedbackPanelState = { ...feedbackPanelState, newSubmitting: false, newContent: "", newScreenshots: [], newScreenshotPreviews: [], newFileNames: [], newEmail: "", newIncludeLogs: true };\n          showToast(state, t("feedback.success"));\n          state.settings.packclawView = "chat";\n          state.requestUpdate();\n        } else {`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'packclawView = "chat"' "$FILE" && ok "R14" || warn "R14: app-render.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R15: Auto-Updater Error Localization
# File: src/auto-updater.ts
# Desc: Translate updater error messages to Chinese. Add manualErrorHandled
#       flag to prevent double error dialogs on manual check.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R15] Patching auto-updater.ts ..."
FILE="$WS/src/auto-updater.ts"
if [ -f "$FILE" ] && ! grep -q 'translateUpdateError' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// 1. Add translateUpdateError function after formatUpdaterError
c = c.replace(
  `function formatUpdaterError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}`,
  `function formatUpdaterError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

function translateUpdateError(err: unknown): string {
  const msg = formatUpdaterError(err);
  if (msg.includes("ERR_UPDATER_CHANNEL_FILE_NOT_FOUND") || msg.includes("404") || msg.includes("Cannot find channel")) {
    return "暂无可用更新，更新服务正在部署中，请稍后再试。";
  }
  if (msg.includes("net::ERR_CONNECTION") || msg.includes("ECONNREFUSED") || msg.includes("ETIMEDOUT") || msg.includes("fetch failed")) {
    return "网络连接失败，请检查网络后重试。";
  }
  if (msg.includes("ERR_UPDATER_INVALID_VERSION")) {
    return "更新信息格式异常，请稍后再试。";
  }
  if (msg.includes("ERR_CHECKSUM_MISMATCH")) {
    return "更新文件校验失败，请重新检查更新。";
  }
  if (msg.includes("ERR_UPDATER_NO_CHECKSUM")) {
    return "更新文件信息不完整，请联系开发者。";
  }
  return msg;
}

let manualErrorHandled = false;`
);

// 2. Change "No Updates" title
c = c.replace(
  `        title: "No Updates",`,
  `        title: "检查更新",`
);

// 3. Modify error handler in autoUpdater.on("error")
c = c.replace(
  `    if (isManualCheck) {
      void dialog.showMessageBox({
        type: "error",
        title: "Update Error",
        message: "检查更新失败",
        detail: err.message,
      });
    }
    isManualCheck = false;
  });`,
  `    if (isManualCheck && !manualErrorHandled) {
      manualErrorHandled = true;
      void dialog.showMessageBox({
        type: "error",
        title: "检查更新失败",
        message: translateUpdateError(err),
      });
    }
    isManualCheck = false;
  });`
);

// 4. Modify checkForUpdates: add reset + modify catch handler
c = c.replace(
  `export function checkForUpdates(manual = false): void {
  isManualCheck = manual;
  void autoUpdater.checkForUpdates().catch((err) => {
    log.error(\`[updater] 检查更新调用失败: \${formatUpdaterError(err)}\`);
    if (manual) {
      void dialog.showMessageBox({
        type: "error",
        title: "Update Error",
        message: "检查更新失败",
        detail: formatUpdaterError(err),
      });
    }
    isManualCheck = false;
  });
}`,
  `export function checkForUpdates(manual = false): void {
  isManualCheck = manual;
  manualErrorHandled = false;
  void autoUpdater.checkForUpdates().catch((err) => {
    log.error(\`[updater] 检查更新调用失败: \${formatUpdaterError(err)}\`);
    if (manual && !manualErrorHandled) {
      manualErrorHandled = true;
      void dialog.showMessageBox({
        type: "error",
        title: "检查更新失败",
        message: translateUpdateError(err),
      });
    }
    isManualCheck = false;
  });
}`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'translateUpdateError' "$FILE" && ok "R15" || warn "R15: auto-updater.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R16: Add nodemailer Dependency & watch:chat Script
# File: package.json
# Desc: Add nodemailer (production) and @types/nodemailer (dev) for feedback
#       email. Add watch:chat script for development hot-reload.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R16] Patching package.json ..."
FILE="$WS/package.json"
if [ -f "$FILE" ]; then
  # Add watch:chat script after build:chat
  sed -i '' 's|"build:chat": "cd chat-ui/ui && npm install --prefer-offline && npx vite build"|"build:chat": "cd chat-ui/ui \&\& npm install --prefer-offline \&\& npx vite build",\n    "watch:chat": "cd chat-ui/ui \&\& npx vite build --watch"|' "$FILE"
  # Add nodemailer to dependencies
  sed -i '' 's|"electron-updater": "\^6.3.9"|"electron-updater": "^6.3.9",\n    "nodemailer": "^8.0.10"|' "$FILE"
  # Add @types/nodemailer to devDependencies
  sed -i '' 's|"@types/node": "\^22.15.0"|"@types/node": "^22.15.0",\n    "@types/nodemailer": "^8.0.0"|' "$FILE"
  ok "R16"
else
  warn "R16: package.json not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R17: @aws-sdk Registry Override
# File: scripts/package-resources.js
# Desc: Add @aws-sdk scoped registry override in generated .npmrc, because
#       npmmirror's @aws-sdk packages are out of sync.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R17] Patching package-resources.js ..."
FILE="$WS/scripts/package-resources.js"
if [ -f "$FILE" ] && ! grep -q '@aws-sdk:registry' "$FILE"; then
  sed -i '' '/disturl=https:\/\/npmmirror.com\/mirrors\/node/a\
    "@aws-sdk:registry=https://registry.npmjs.org",
' "$FILE"
  ok "R17"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Patch Summary"
echo "══════════════════════════════════════════════════════════"
if [ -z "$FAILURES" ]; then
  echo "  All 17 patches applied successfully."
else
  echo "  Failed patches:"
  echo -e "$FAILURES"
  echo ""
  echo "  See patches/REQUIREMENTS.md for manual implementation."
fi
echo "══════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    cd workspace && npm install && npm run build"
