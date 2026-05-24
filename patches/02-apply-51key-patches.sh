#!/bin/bash
#
# 51key provider integration — upstream file patches
#
# This script applies minimal hook-point patches to upstream files,
# then copies PackClaw-only new files from overlay/.
#
# Run AFTER: bash scripts/pull-upstream.sh
# Run BEFORE: npm run build
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"

echo "==> [51key] Patching upstream files..."

# ─── 1. chat-ui/ui/src/ui/chat/grouped-render.ts ───
# Add import of 51key empty response renderer and hook it into renderGroupedMessage
patch -p2 -d "$WS" < "$ROOT/patches/51key-upstream-changes.patch" --reject-file=- 2>/dev/null || {
  echo "  ⚠ Patch may have partially failed, trying file-by-file..."
}

# ─── 2. Copy new 51key files from overlay (if not already present) ───
echo "==> [51key] Copying new files from overlay..."
rsync -av --ignore-existing \
  "$ROOT/overlay/chat-ui/" \
  "$WS/chat-ui/"

# ─── 3. Verify key files exist ───
FILES=(
  "chat-ui/ui/src/ui/views/setup/provider-51key-config.ts"
  "chat-ui/ui/src/ui/views/setup/setup-51key-section.ts"
  "chat-ui/ui/src/ui/views/settings/settings-51key-section.ts"
  "chat-ui/ui/src/ui/chat/chat-51key-balance.ts"
  "chat-ui/ui/src/ui/i18n-51key.ts"
)
for f in "${FILES[@]}"; do
  if [ ! -f "$WS/$f" ]; then
    echo "  ✗ MISSING: $f"
    exit 1
  fi
done

echo "==> [51key] Done. Run 'npm run build' to compile."
