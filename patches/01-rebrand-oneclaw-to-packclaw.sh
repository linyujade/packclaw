#!/bin/bash
# 01-rebrand-oneclaw-to-packclaw.sh
# Global rebrand: OneClaw → PackClaw in workspace/
#
# Replacement rules (case-sensitive):
#   ONECLAW  → PACKCLAW
#   OneClaw  → PackClaw
#   oneclaw  → packclaw
#   oneClaw  → packClaw
#   Oneclaw  → Packclaw
#
# Also renames files and directories containing "oneclaw" in their names.

set -euo pipefail

WS="${1:-workspace}"

if [ ! -d "$WS" ]; then
  echo "Error: '$WS' not found" >&2
  exit 1
fi

SKIP_EXTS="png|ico|icns|jpg|jpeg|gif|svg|woff2?|ttf|eot|otf|zip|dmg|exe|p12|asar|mp3|mp4|webp|pdf|snap"

# ── Step 1: Content replacement ──────────────────────────────────────

echo "==> Replacing content in text files..."

find "$WS" -type f \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/out/*" \
  -not -path "*/.cache/*" \
  -not -path "*/resources/targets/*" \
  -not -path "*/.dev-state/*" \
  -not -path "*/.worktree*/*" \
  -not -regex ".*\\.\\(${SKIP_EXTS}\\)$" \
  -exec perl -pi -e '
    s/ONECLAW/PACKCLAW/g;
    s/OneClaw/PackClaw/g;
    s/oneclaw/packclaw/g;
    s/oneClaw/packClaw/g;
    s/Oneclaw/Packclaw/g;
  ' {} +

echo "    Done."

# ── Step 2: Rename files (depth-first) ───────────────────────────────

rename_path() {
  printf '%s' "$1" | sed \
    -e 's/ONECLAW/PACKCLAW/g' \
    -e 's/OneClaw/PackClaw/g' \
    -e 's/oneclaw/packclaw/g' \
    -e 's/oneClaw/packClaw/g' \
    -e 's/Oneclaw/Packclaw/g'
}

echo "==> Renaming files..."

find "$WS" -depth -type f -name "*oneclaw*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" | while IFS= read -r f; do
  dir=$(dirname "$f")
  base=$(basename "$f")
  newbase=$(rename_path "$base")
  if [ "$base" != "$newbase" ]; then
    mv "$f" "$dir/$newbase"
    echo "    $base → $newbase"
  fi
done

# ── Step 3: Rename directories (depth-first) ─────────────────────────

echo "==> Renaming directories..."

find "$WS" -depth -type d -name "*oneclaw*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" | while IFS= read -r d; do
  parent=$(dirname "$d")
  base=$(basename "$d")
  newbase=$(rename_path "$base")
  if [ "$base" != "$newbase" ]; then
    mv "$d" "$parent/$newbase"
    echo "    $base/ → $newbase/"
  fi
done

# ── Step 4: Fix electron-builder path in dist scripts ────────────────

echo "==> Patching package.json: electron-builder → npx electron-builder..."

if [ -f "$WS/package.json" ]; then
  perl -pi -e 's/(?<!npx )electron-builder --win/npx electron-builder --win/g' "$WS/package.json"
  echo "    Done."
else
  echo "    Skipped (package.json not found)."
fi

# ── Step 5: Dev mode ASAR support ────────────────────────────────────

echo "==> Patching constants.ts: dev mode ASAR support..."

CONSTANTS_FILE="$WS/src/constants.ts"
if [ -f "$CONSTANTS_FILE" ]; then
  perl -pi -e 'BEGIN { $/=undef } s/function resolveGatewayRoot\(\): string \{\n  const res = resolveResourcesPath\(\);\n  \/\/ dev 模式用真实 Node\.js，无法读取 asar 虚拟路径，直接走散文件\n  if \(!app\.isPackaged\) \{\n    return path\.join\(res, "gateway"\);\n  \}\n  const asarPath = path\.join\(res, "gateway\.asar"\);\n  if \(path\.extname\(asarPath\) === "\.asar" && fs\.existsSync\(asarPath\)\) \{\n    return asarPath;\n  \}\n  return path\.join\(res, "gateway"\);\n\}/function resolveGatewayRoot(): string {\n  const res = resolveResourcesPath();\n  const asarPath = path.join(res, "gateway.asar");\n  if (path.extname(asarPath) === ".asar" \&\& fs.existsSync(asarPath)) {\n    return asarPath;\n  }\n  return path.join(res, "gateway");\n}/sg' "$CONSTANTS_FILE"
  echo "    Done."
else
  echo "    Skipped (src/constants.ts not found)."
fi

echo "==> Rebrand complete."
