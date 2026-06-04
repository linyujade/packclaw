#!/usr/bin/env bash

set -u

FAILED=0

run_task() {
  local name="$1"
  echo "[parallel] start ${name}"
  if npm run "${name}"; then
    echo "[parallel] done ${name}"
  else
    echo "[parallel] fail ${name}"
    FAILED=1
  fi
}

# macOS arm64 和 x64 共享同一个 Electron 缓存，并行会导致竞态条件
# （Electron.app 内二进制文件缺失），因此同平台两个 arch 必须串行。
# macOS 和 Windows 之间无冲突，可以并行。

echo "[parallel] === macOS 构建（arm64 → x64 串行） ==="
( run_task "dist:mac:arm64" && run_task "dist:mac:x64" ) &
MAC_PID=$!

echo "[parallel] === Windows 构建（x64 → arm64 串行） ==="
( run_task "dist:win:x64" && run_task "dist:win:arm64" ) &
WIN_PID=$!

wait $MAC_PID
wait $WIN_PID

if [[ "${FAILED}" -ne 0 ]]; then
  echo "[parallel] 至少一个打包任务失败"
  exit 1
fi

echo "[parallel] 四个目标打包全部完成"
