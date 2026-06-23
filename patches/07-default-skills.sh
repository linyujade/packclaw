#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 07-default-skills.sh
#
# 启动时自动禁用 13 个非默认 bundled 技能，只保留 9 个通用技能默认启用。
# 用户可在设置→技能页面手动启用需要的技能。
#
# Run AFTER: 06-about-page-improvements.sh
#
# See patches/07-default-skills.md for details.
# ═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"
FAILURES=""

warn() { echo "  ⚠ [FAIL] $1"; FAILURES="$FAILURES\n  $1"; }
ok()   { echo "  ✓ $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# R40: 默认禁用非默认 bundled 技能
# File: src/main.ts
# Desc: 添加 migrateDisableNonDefaultBundledSkills() 迁移函数，在启动时将
#       13 个非默认 bundled 技能的 skills.entries[name].enabled 设为 false。
#       已有 enabled 字段的不覆盖（幂等，尊重用户手动设置）。
#       在两个启动路径（packclaw + legacy-packclaw）调用。
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R40] Patching main.ts (default skill allowlist) ..."
FILE="$WS/src/main.ts"
if [ -f "$FILE" ] && ! grep -q 'migrateDisableNonDefaultBundledSkills' "$FILE"; then
  node -e '
    const fs = require("fs");
    const f = process.argv[1];
    let s = fs.readFileSync(f, "utf8");

    // 1. Insert migrateDisableNonDefaultBundledSkills function after migrateDisableKimiClaw
    const newFunc = `
// PackClaw 默认只启用 9 个通用 bundled 技能，其余 13 个默认禁用。
// 用户可在设置→技能页面手动启用需要的技能。
// 幂等：已有 enabled 字段的技能不覆盖（包括用户手动启用的）。
const NON_DEFAULT_BUNDLED_SKILLS = [
  "apple-notes", "apple-reminders", "camsnap", "canvas", "discord",
  "github", "healthcheck", "imsg", "model-usage", "notion",
  "peekaboo", "tmux", "video-frames",
];

function migrateDisableNonDefaultBundledSkills(): void {
  try {
    const config = readUserConfig();
    if (!config || typeof config !== "object") return;
    config.skills ??= {};
    (config.skills as any).entries ??= {};
    const entries = (config.skills as any).entries;
    let changed = false;
    for (const name of NON_DEFAULT_BUNDLED_SKILLS) {
      if (!entries[name]) {
        entries[name] = { enabled: false };
        changed = true;
      } else if (entries[name].enabled === undefined) {
        entries[name].enabled = false;
        changed = true;
      }
    }
    if (changed) {
      writeUserConfig(config);
      log.info(\`[migrate] 已禁用 \${NON_DEFAULT_BUNDLED_SKILLS.length} 个非默认 bundled 技能\`);
    }
  } catch {
    // 迁移失败不阻塞启动
  }
}`;

    // Insert after migrateDisableKimiClaw function closing brace
    s = s.replace(
      /(\n\/\/ 存量用户迁移：openclaw 2026\.4\.x 的 dingtalk-connector)/,
      newFunc + "\n$1"
    );

    // 2. Add call in both startup paths, after migrateDisableKimiClaw()
    //    First occurrence (packclaw path)
    s = s.replace(
      /(migrateDisableKimiClaw\(\);\n)(\s+void reconcileCliOnAppLaunch)/,
      "$1      migrateDisableNonDefaultBundledSkills();\n$2"
    );
    //    Second occurrence (legacy-packclaw path)
    s = s.replace(
      /(migrateDisableKimiClaw\(\);\n)(\s+void reconcileCliOnAppLaunch\.catch)/,
      "$1      migrateDisableNonDefaultBundledSkills();\n$2"
    );

    fs.writeFileSync(f, s, "utf8");
  ' "$FILE"

  COUNT=$(grep -c 'migrateDisableNonDefaultBundledSkills' "$FILE")
  if [ "$COUNT" -ge 3 ]; then
    ok "R40 (function + 2 call sites = $COUNT matches)"
  else
    warn "R40: expected ≥3 matches, found $COUNT"
  fi
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
  echo "✅ All default skills patches applied successfully."
fi
