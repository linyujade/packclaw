#!/bin/bash
#
# Feedback email + disable kimi-claw — upstream file patches
#
# 1) 反馈提交改为通过 SMTP 发邮件到 linyujade@163.com
# 2) 启动时自动禁用 kimi-claw 插件，防止后台消耗 API 额度
#
# Run AFTER: bash scripts/pull-upstream.sh (step 02)
# Run BEFORE: npm run build
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WS="$ROOT/workspace"

echo "==> [03] Patching upstream files (feedback email + disable kimi-claw)..."

patch --batch -p1 -d "$WS" < "$ROOT/patches/03-feedback-email-and-disable-kimi-claw.patch" || {
  echo "  ⚠ Patch failed. Check rejects and apply manually."
}

echo "==> [03] Installing nodemailer dependency..."
cd "$WS"
npm install

echo "==> [03] Done."
