#!/bin/bash

# 🔁 标准流程（结合你的系统）
# 第一步：更新 upstream
git subtree pull --prefix=upstream oneclaw main --squash
# 第二步：备份旧 workspace 并重建
# 删除构建相关产物
rm -rf workspace/dist
rm -rf workspace/out
rm -rf workspace/*.tsbuildinfo
rm -rf workspace/resources/runtime
rm -rf workspace/resources/gateway
rm -rf workspace/.DS_Store
# 备份旧 workspace 代码到 workspace-时间戳
mv workspace "workspace-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
cp -r upstream workspace
# 第三步：应用 patch , 重命名文件，并替换oneclaw为packclaw（区分大小写）
sh ./patches/01-rebrand-oneclaw-to-packclaw.sh workspace

# 第三步半：应用所有 PackClaw 定制补丁（R01-R17）
sh ./patches/02-apply-packclaw-customizations.sh

# 第三步又半：优化构建缓存（R18-R20）
sh ./patches/03-optimize-build-caching.sh

# 第三步再半：macOS 手动安装更新流程（R21-R28）
sh ./patches/04-macos-manual-update-installer.sh

# 第四步：覆盖 overlay
rsync -av ./overlay/ workspace/

# 第五步：复制安装依赖、构建缓存、node_modules
cp -r workspace-$(date +%Y%m%d)*/.cache workspace/.cache
cp -r workspace-$(date +%Y%m%d)*/node_modules workspace/node_modules
npm install