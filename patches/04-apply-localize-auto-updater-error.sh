#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$SCRIPT_DIR/04-localize-auto-updater-error.patch"

if [ ! -f "$PATCH" ]; then
  echo "Patch file not found: $PATCH"
  exit 1
fi

git apply --directory workspace "$PATCH"
