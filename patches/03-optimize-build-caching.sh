#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 03-optimize-build-caching.sh
#
# Optimizes build speed by fixing incremental detection gaps and adding
# a global fast-path for fully cached builds.
# Run AFTER: 02-apply-packclaw-customizations.sh
#
# Each section is labeled R18–R20. See patches/REQUIREMENTS.md for full details.
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
# R18: Fix macOS parallel build missing x64 target
# File: scripts/dist-all-parallel.sh
# Desc: macOS arm64 was running standalone instead of serial arm64→x64.
#       Fix to match Windows pattern: ( dist:mac:arm64 && dist:mac:x64 ) &
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R18] Patching dist-all-parallel.sh ..."
FILE="$WS/scripts/dist-all-parallel.sh"
if [ -f "$FILE" ] && grep -q '^run_task "dist:mac:arm64" &$' "$FILE"; then
  sed -i '' 's/^run_task "dist:mac:arm64" \&$/( run_task "dist:mac:arm64" \&\& run_task "dist:mac:x64" ) \&/' "$FILE"
  grep -q 'run_task "dist:mac:x64"' "$FILE" && ok "R18" || warn "R18: dist-all-parallel.sh patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R19: ASAR stamp backup + global fast-path for package-resources
# File: scripts/package-resources.js
# Desc: Three changes to speed up repeated builds:
#   1. readGatewayStamp() falls back to .gateway-stamp.bak (ASAR deletes gateway/)
#   2. packGatewayAsar() backs up stamp before deleting gateway/
#   3. New canSkipAll() + early return in main() when all caches hit
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R19] Patching package-resources.js ..."
FILE="$WS/scripts/package-resources.js"
if [ -f "$FILE" ] && ! grep -q 'canSkipAll' "$FILE"; then
  node -e "$(cat << 'NODEEOF'
const fs = require("fs");
const f = process.argv[1];
let c = fs.readFileSync(f, "utf8");

// --- Patch 1: readGatewayStamp fallback to backup ---
c = c.replace(
  `// 读取 gateway 依赖平台戳
function readGatewayStamp(stampPath) {
  try {
    return fs.readFileSync(stampPath, "utf-8").trim();
  } catch {
    return "";
  }
}`,
  `// 读取 gateway 依赖平台戳
// ASAR 模式打包后 gateway/ 目录被删除，stamp 会被移到 targetBase 下备份。
// 优先读原始位置，fallback 到备份位置。
function readGatewayStamp(stampPath) {
  try {
    return fs.readFileSync(stampPath, "utf-8").trim();
  } catch {
    // fallback: ASAR 模式下 stamp 已备份到 targetBase/.gateway-stamp.bak
    const backupPath = path.join(path.dirname(path.dirname(stampPath)), ".gateway-stamp.bak");
    try {
      return fs.readFileSync(backupPath, "utf-8").trim();
    } catch {
      return "";
    }
  }
}`
);

// --- Patch 2: backup stamp before rmDir in packGatewayAsar ---
c = c.replace(
  `  // 删除散文件目录
  rmDir(gatewayDir);
  log("已删除 gateway/ 散文件目录");`,
  `  // 备份 stamp 文件（ASAR 打包后 gateway/ 被删除，下次构建需要 stamp 做增量检测）
  const stampPath = path.join(gatewayDir, ".gateway-stamp");
  const stampBackup = path.join(targetBase, ".gateway-stamp.bak");
  if (fs.existsSync(stampPath)) {
    fs.copyFileSync(stampPath, stampBackup);
  }

  // 删除散文件目录
  rmDir(gatewayDir);
  log("已删除 gateway/ 散文件目录");`
);

// --- Patch 3: add canSkipAll function before main ---
const canSkipAllCode = `
// ─── 全局快速检测 ───

// 检查所有步骤的缓存是否全部命中，命中则跳过整个打包流程。
// 返回 true 表示可以完全跳过。
function canSkipAll(opts, targetPaths) {
  const { targetBase, runtimeDir, gatewayDir, iconPath, buildConfigPath } = targetPaths;

  // ASAR 模式下 gateway/ 不存在，用 gateway.asar 存在性代替
  const asarMode = opts.asar;
  const asarPath = path.join(targetBase, "gateway.asar");
  const stampBackup = path.join(targetBase, ".gateway-stamp.bak");

  // Step 1: runtime stamp
  const nodeStampFile = path.join(runtimeDir, ".node-stamp");
  if (!fs.existsSync(nodeStampFile)) return false;

  // Step 2: gateway stamp（散文件 or ASAR 备份）
  const gatewayStampPath = path.join(gatewayDir, ".gateway-stamp");
  const gatewayStamp = readGatewayStamp(gatewayStampPath);
  if (!gatewayStamp) return false;
  const sourceInfo = getPackageSource();
  const expectedStamp = \`\${opts.platform}-\${opts.arch}|\${sourceInfo.stampSource}\`;
  if (gatewayStamp !== expectedStamp) return false;

  // ASAR 模式：gateway.asar 必须存在
  if (asarMode && !fs.existsSync(asarPath)) return false;

  // 非 ASAR 模式：gateway entry.js 必须存在
  if (!asarMode && !fs.existsSync(path.join(gatewayDir, "node_modules", "openclaw", "dist", "entry.js"))) return false;

  // Step 4: app icon
  if (!fs.existsSync(iconPath)) return false;

  // Step 7: officecli stamp
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
  const officecliVersion = pkg.packclaw?.officecli;
  if (officecliVersion) {
    const officecliOutputDir = path.join(targetBase, "officecli");
    const officecliBin = path.join(officecliOutputDir, opts.platform === "win32" ? "officecli.exe" : "officecli");
    const officecliStamp = path.join(officecliOutputDir, ".officecli-stamp");
    if (!fs.existsSync(officecliBin) || !fs.existsSync(officecliStamp)) return false;
    const stampPrefix = \`\${officecliVersion}-\${opts.platform}-\${opts.arch}\`;
    const rawStamp = fs.readFileSync(officecliStamp, "utf-8").trim();
    if (!rawStamp.startsWith(stampPrefix)) return false;
  }

  return true;
}

`;

c = c.replace(
  "// ─── 主流程 ───\n",
  canSkipAllCode + "// ─── 主流程 ───\n"
);

// --- Patch 4: add early return in main() after banner ---
c = c.replace(
  `  log("========================================");
  console.log();

  // Step 1: 下载 Node.js 22 运行时`,
  `  log("========================================");
  console.log();

  // 全局快速检测：所有步骤缓存命中则跳过
  if (canSkipAll(opts, targetPaths)) {
    log("所有资源已就绪（缓存全部命中），跳过打包");
    verifyOutput(targetPaths, opts);
    console.log();
    log("资源打包完成！");
    return;
  }

  // Step 1: 下载 Node.js 22 运行时`
);

fs.writeFileSync(f, c);
NODEEOF
)" "$FILE"
  grep -q 'canSkipAll' "$FILE" && ok "R19" || warn "R19: package-resources.js patch failed"
else
  echo "  (skipped: already patched or file missing)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# R20: Remove moonshot provider label
# File: chat-ui/ui/src/ui/views/setup/setup-constants.ts
# Desc: Remove moonshot from getProviderLabels() — PackClaw doesn't use it.
# ═══════════════════════════════════════════════════════════════════════════════
echo "==> [R20] Patching setup-constants.ts ..."
FILE="$WS/chat-ui/ui/src/ui/views/setup/setup-constants.ts"
if [ -f "$FILE" ] && grep -q 'moonshot: t("setup.provider.label.moonshot")' "$FILE"; then
  sed -i '' '/moonshot: t("setup.provider.label.moonshot"),/d' "$FILE"
  ! grep -q 'moonshot: t("setup.provider.label.moonshot")' "$FILE" && ok "R20" || warn "R20: setup-constants.ts patch failed"
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
  echo "  All 3 patches (R18–R20) applied successfully."
else
  echo "  Failed patches:"
  echo -e "$FAILURES"
  echo ""
  echo "  See patches/REQUIREMENTS.md for manual implementation."
fi
echo "══════════════════════════════════════════════════════════"
