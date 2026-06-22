#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 05-skill-store-enhancements.sh
#
# Overhauls the skill store: path alignment, display name persistence, ambiguous
# slug support, frontmatter fix, unified metadata (version + downloads) across
# store and installed lists.
#
# NOTE: src/skill-store.ts is a full overlay file (overlay/src/skill-store.ts),
#       applied via rsync. This script handles all OTHER files.
#
# Run AFTER: 04-macos-manual-update-installer.sh
# Run BEFORE: rsync overlay/ → workspace/
#
# Each section is labeled R29–R36. See patches/REQUIREMENTS.md for full details.
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
# R29: clawhub workdir alignment
# File: src/gateway-process.ts
# Desc: Change clawhub wrapper workdir from ~/.openclaw/workspace to ~/.openclaw
#       so skills are installed to ~/.openclaw/skills (gateway "openclaw-managed"
#       source) instead of ~/.openclaw/workspace/skills ("openclaw-workspace").
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R29] Patching gateway-process.ts (clawhub workdir) ..."
FILE="$WS/src/gateway-process.ts"
if [ -f "$FILE" ] && grep -q 'resolveUserStateDir(), "workspace"' "$FILE"; then
  perl -0777 -pi -e \
    's|// 默认 workdir 指向 ~/.openclaw/workspace\n  const workdir = path\.join\(resolveUserStateDir\(\), "workspace"\);|// workdir 指向 ~/.openclaw，技能装到 ~/.openclaw/skills（网关 openclaw-managed 目录）\n  const workdir = resolveUserStateDir();|s' \
    "$FILE"
  grep -q 'const workdir = resolveUserStateDir();' "$FILE" && ok "R29" || warn "R29: workdir not changed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R30: Add skillStoreGetDisplayNames IPC bridge
# File: src/preload.ts
# Desc: Expose skill-store:get-display-names IPC to renderer. Returns
#       { data: displayNames, meta: storeMeta } for injecting friendly names
#       and version/downloads into the installed skills list.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R30] Patching preload.ts (skillStoreGetDisplayNames) ..."
FILE="$WS/src/preload.ts"
if [ -f "$FILE" ] && ! grep -q 'skillStoreGetDisplayNames' "$FILE"; then
  perl -0777 -pi -e \
    's/(skillStoreListInstalled: \(\) =>\n    ipcRenderer\.invoke\("skill-store:list-installed"\),)/$1\n  skillStoreGetDisplayNames: () =>\n    ipcRenderer.invoke("skill-store:get-display-names"),/s' \
    "$FILE"
  grep -q 'skillStoreGetDisplayNames' "$FILE" && ok "R30" || warn "R30: IPC bridge not added"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R31: skill-store-view.ts — types, callbacks, card rendering
# File: chat-ui/ui/src/ui/skill-store-view.ts
# Desc: Add ownerHandle/ref to SkillItem, update callback signatures to pass
#       version/downloads/ownerHandle, render @author in card meta, show
#       "uninstalling" state, match installed cards by ref || slug.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R31] Patching skill-store-view.ts ..."
FILE="$WS/chat-ui/ui/src/ui/skill-store-view.ts"
if [ -f "$FILE" ] && ! grep -q 'ownerHandle' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");

    // 1. Add ownerHandle + ref to SkillItem type
    s = s.replace(
      /  author: string;\n\};/,
      `  author: string;\n  ownerHandle: string;\n  ref: string;\n};`
    );

    // 2. Update callback signatures
    s = s.replace(
      /onInstall: \(slug: string\) => void;/,
      `onInstall: (slug: string, displayName: string, ownerHandle: string, version: string, downloads: number) => void;`
    );
    s = s.replace(
      /onUninstall: \(slug: string\) => void;/,
      `onUninstall: (slug: string, ref: string) => void;`
    );

    // 3. Add @author in card meta
    s = s.replace(
      /(<div class="skill-store__card-meta">\n)(\s+\$\{skill\.version)/,
      `$1            ${skill.ownerHandle ? html\`<span class="skill-store__card-author">@${skill.ownerHandle}</span>\` : nothing}\n          $2`
    );

    // 4. Show "uninstalling" state on button
    s = s.replace(
      /\?\$\{t\("skillStore\.uninstall"\)\}<\/button>/,
      `?${installing ? t("skillStore.uninstalling") : t("skillStore.uninstall")}</button>`
    );

    // 5. Match installed/installing by ref || slug, pass version/downloads
    s = s.replace(
      /state\.installedSlugs\.has\(skill\.slug\),\n          state\.installingSlugs\.has\(skill\.slug\),\n          \(\) => callbacks\.onInstall\(skill\.slug\),\n          \(\) => callbacks\.onUninstall\(skill\.slug\),/,
      `state.installedSlugs.has(skill.ref) || state.installedSlugs.has(skill.slug),\n          state.installingSlugs.has(skill.ref || skill.slug),\n          () => callbacks.onInstall(skill.slug, skill.name, skill.ownerHandle, skill.version, skill.downloads),\n          () => callbacks.onUninstall(skill.slug, skill.ref || skill.slug),`
    );

    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  grep -q 'ownerHandle' "$FILE" && ok "R31" || warn "R31: skill-store-view.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R32: app-render.ts — install/uninstall/displayName/meta/search
# File: chat-ui/ui/src/ui/app-render.ts
# Desc: Pass displayName/ownerHandle/version/downloads through install flow,
#       use ref for uninstall busy key, refresh installed slugs after uninstall,
#       show all skills in installed view (not just eligible), normalize search
#       separators, render displayName + version + downloads in installed cards.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R32] Patching app-render.ts ..."
FILE="$WS/chat-ui/ui/src/ui/app-render.ts"
if [ -f "$FILE" ] && ! grep -q 'skillStoreGetDisplayNames' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");

    // 1. Add skillStoreGetDisplayNames type declaration
    s = s.replace(
      /skillStoreListInstalled\?: \(\) => Promise<any>;/,
      `skillStoreListInstalled?: () => Promise<any>;\n      skillStoreGetDisplayNames?: () => Promise<{ success: boolean; data?: Record<string, string> }>;`
    );

    // 2. Rewrite installSkillFromStore signature + body
    s = s.replace(
      /async function installSkillFromStore\(state: AppViewState, slug: string\) \{/,
      `async function installSkillFromStore(state: AppViewState, slug: string, displayName?: string, ownerHandle?: string, version?: string, downloads?: number) {`
    );
    s = s.replace(
      /skillStoreState\.installingSlugs\.add\(slug\);\n  state\.requestUpdate\(\);\n  try \{\n    const result = await window\.packclaw\.skillStoreInstall\(\{ slug \}\);/,
      `const installKey = ownerHandle ? \`@\${ownerHandle}/\${slug}\` : slug;\n  skillStoreState.installingSlugs.add(installKey);\n  state.requestUpdate();\n  try {\n    const result = await window.packclaw.skillStoreInstall({ slug, displayName, ownerHandle, version, downloads });`
    );
    s = s.replace(
      /skillStoreState\.installedSlugs\.add\(slug\);/,
      `skillStoreState.installedSlugs.add(installKey);`
    );
    s = s.replace(
      /skillStoreState\.installingSlugs\.delete\(slug\);(\s*state\.requestUpdate\(\);\s*\})\n}/,
      `skillStoreState.installingSlugs.delete(installKey);$1\n}`
    );

    // 3. Rewrite uninstallSkillFromStore signature + body
    s = s.replace(
      /async function uninstallSkillFromStore\(state: AppViewState, slug: string\) \{/,
      `async function uninstallSkillFromStore(state: AppViewState, slug: string, ref?: string) {`
    );
    s = s.replace(
      /skillStoreState\.installingSlugs\.add\(slug\);\n  state\.requestUpdate\(\);\n  try \{\n    const result = await window\.packclaw\.skillStoreUninstall\(\{ slug \}\);\n    if \(result\?\.success\) \{\n      skillStoreState\.installedSlugs\.delete\(slug\);/,
      `const busyKey = ref || slug;\n  skillStoreState.installingSlugs.add(busyKey);\n  state.requestUpdate();\n  try {\n    const result = await window.packclaw.skillStoreUninstall({ slug });\n    if (result?.success) {\n      // 从后端重新同步已安装列表（返回 ref 格式，确保歧义 slug 的卡片状态正确）\n      await refreshInstalledSlugs();`
    );
    s = s.replace(
      /skillStoreState\.installingSlugs\.delete\(slug\);\n  state\.requestUpdate\(\);\n\}\n\n\/\/ 根据名称或 slug/,
      `skillStoreState.installingSlugs.delete(busyKey);\n  state.requestUpdate();\n}\n\n// 根据名称或 slug`
    );

    // 4. renderInstalledSkillsView: show all skills, normalize search
    s = s.replace(
      /\/\/ 1\. 过滤被阻止的 skill（blockedByAllowlist 或 eligible === false）\n  const visibleSkills = allSkills\.filter\(\(s: SkillStatusEntry\) => s\.eligible !== false\);\n  const filter = \(\(state as any\)\.skillsFilter \?\? ""\)\.trim\(\)\.toLowerCase\(\);\n  const filtered = filter\n    \? visibleSkills\.filter\(\(s: SkillStatusEntry\) =>\n        \[s\.name, s\.description, s\.source\]\.join\(" "\)\.toLowerCase\(\)\.includes\(filter\),\n      \)/,
      `// 1. 已安装管理视图显示全部技能（含禁用、缺依赖的），让用户可以重新启用或补配置\n  const visibleSkills = allSkills;\n  // 搜索时统一分隔符：技能 name 是 slug（如 stock-watcher），商店显示名带空格（Stock Watcher）\n  // 把连字符/下划线/多空格都归一为单空格，使 "stock watcher" 能匹配 "stock-watcher"\n  const norm = (s: string) => s.toLowerCase().replace(/[-_\\s]+/g, " ").trim();\n  const filterQ = norm((state as any).skillsFilter ?? "");\n  const filtered = filterQ\n    ? visibleSkills.filter((s: SkillStatusEntry) =>\n        norm([(s as any).displayName ?? s.name, s.name, s.description, s.source].join(" ")).includes(filterQ),\n      )`
    );

    // 5. Installed card: displayName + version + downloads
    s = s.replace(
      /<div class="skill-store__card-name">\$\{skill\.name \?\? key\}<\/div>/,
      `<div class="skill-store__card-name">${(skill as any).displayName ?? skill.name ?? key}</div>`
    );
    s = s.replace(
      /<div class="skill-store__card-meta">\n                      <span class="skills-badge">\$\{skill\.source\}<\/span>\n                    <\/div>/,
      `<div class="skill-store__card-meta">\n                      <span class="skills-badge">${skill.source}</span>\n                      ${(skill as any).version ? html\`v${(skill as any).version}\` : nothing}\n                      ${(skill as any).downloads > 0 ? html\`<span class="skill-store__card-downloads">${(skill as any).downloads >= 1000 ? \`\${((skill as any).downloads / 1000).toFixed(1)}k\` : (skill as any).downloads} ${t("skillStore.downloads")}</span>\` : nothing}\n                    </div>`
    );

    // 6. Update callbacks in renderApp
    s = s.replace(
      /onInstall: \(slug\) => void installSkillFromStore\(state, slug\),\n                            onUninstall: \(slug\) => void uninstallSkillFromStore\(state, slug\),/,
      `onInstall: (slug, displayName, ownerHandle, version, downloads) => void installSkillFromStore(state, slug, displayName, ownerHandle, version, downloads),\n                            onUninstall: (slug, ref) => void uninstallSkillFromStore(state, slug, ref),`
    );

    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"
  grep -q 'skillStoreGetDisplayNames' "$FILE" && ok "R32" || warn "R32: app-render.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R33: controllers/skills.ts — inject displayName + meta in loadSkills
# File: chat-ui/ui/src/ui/controllers/skills.ts
# Desc: After fetching skills.status from gateway, load displayNames and
#       storeMeta from IPC and inject displayName, version, downloads into each
#       skill entry so the installed list shows friendly names + unified metadata.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R33] Patching controllers/skills.ts ..."
FILE="$WS/chat-ui/ui/src/ui/controllers/skills.ts"
if [ -f "$FILE" ] && ! grep -q 'skillStoreGetDisplayNames' "$FILE"; then
  perl -0777 -pi -e \
    's/(const res = await state\.client\.request<SkillStatusReport \| undefined>\("skills\.status", \{\}\);\n    if \(res\) \{)\n/$1\n      \/\/ 加载展示名映射 + 商店元数据（version, downloads），注入到每个 skill 条目\n      let displayNames: Record<string, string> = {};\n      let storeMeta: Record<string, { version?: string; downloads?: number }> = {};\n      try {\n        const r = await (window as any).packclaw?.skillStoreGetDisplayNames?.();\n        if (r?.success \&\& r.data) displayNames = r.data as Record<string, string>;\n        if (r?.meta) storeMeta = r.meta as Record<string, { version?: string; downloads?: number }>;\n      } catch { \/* ignore *\/ }\n      for (const s of res.skills ?? []) {\n        const slug = (String((s as any).skillKey ?? "")).split(":").pop() ?? "";\n        \/\/ 注入 displayName\n        const dn = displayNames[s.name ?? ""] ?? displayNames[slug] ?? displayNames[s.id ?? ""];\n        if (dn) (s as any).displayName = dn;\n        \/\/ 注入 version + downloads\n        const meta = storeMeta[s.name ?? ""] ?? storeMeta[slug] ?? storeMeta[s.id ?? ""];\n        if (meta) {\n          if (meta.version) (s as any).version = meta.version;\n          if (meta.downloads !== undefined) (s as any).downloads = meta.downloads;\n        }\n      }\n/' \
    "$FILE"
  grep -q 'skillStoreGetDisplayNames' "$FILE" && ok "R33" || warn "R33: controllers/skills.ts patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R34: i18n.ts — add "uninstalling" key
# File: chat-ui/ui/src/ui/i18n.ts
# Desc: Add skillStore.uninstalling to both zh and en dictionaries for the
#       uninstall button busy state.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R34] Patching i18n.ts (uninstalling key) ..."
FILE="$WS/chat-ui/ui/src/ui/i18n.ts"
if [ -f "$FILE" ] && ! grep -q 'skillStore.uninstalling' "$FILE"; then
  # Chinese
  perl -pi -e \
    's/("skillStore\.uninstall": "卸载",)/$1\n    "skillStore.uninstalling": "卸载中…",/' \
    "$FILE"
  # English
  perl -pi -e \
    's/("skillStore\.uninstall": "Uninstall",)/$1\n    "skillStore.uninstalling": "Uninstalling…",/' \
    "$FILE"
  grep -q 'skillStore.uninstalling' "$FILE" && ok "R34" || warn "R34: i18n key not added"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R35: styles.css — disabled uninstall button opacity
# File: chat-ui/ui/src/styles.css
# Desc: When the uninstall button is disabled (during uninstall), reduce opacity
#       and show not-allowed cursor.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R35] Patching styles.css (disabled button) ..."
FILE="$WS/chat-ui/ui/src/styles.css"
if [ -f "$FILE" ] && ! grep -q 'skill-store__btn--installed:disabled' "$FILE"; then
  perl -0777 -pi -e \
    's/(\.skill-store__btn--installed \{)/.skill-store__btn--installed:disabled {\n  opacity: 0.6;\n  cursor: not-allowed;\n}\n\n$1/' \
    "$FILE"
  grep -q 'skill-store__btn--installed:disabled' "$FILE" && ok "R35" || warn "R35: CSS rule not added"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R36: package.json — add extract-zip dependency
# File: package.json
# Desc: skill-store.ts imports extract-zip for manual skill installation
#       (ambiguous slug fallback). It is a transitive dep of electron but we
#       declare it explicitly for stability.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R36] Patching package.json (extract-zip dep) ..."
FILE="$WS/package.json"
if [ -f "$FILE" ] && ! grep -q '"extract-zip"' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    const pkg = JSON.parse(fs.readFileSync(f, "utf8"));
    if (!pkg.dependencies) pkg.dependencies = {};
    pkg.dependencies["extract-zip"] = "^2.0.1";
    fs.writeFileSync(f, JSON.stringify(pkg, null, 2) + "\n", "utf8");
  ' "$FILE"
  grep -q '"extract-zip"' "$FILE" && ok "R36" || warn "R36: extract-zip not added to package.json"
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
  echo "✅ All skill store enhancement patches applied successfully."
fi
