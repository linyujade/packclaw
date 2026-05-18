#!/bin/bash

# 🔁 标准流程（结合你的系统）
# 第一步：更新 upstream
git subtree pull --prefix=upstream oneclaw main --squash
# 第二步：重建 workspace
rm -rf workspace
cp -r upstream workspace
# 第三步：应用 patch ,sed 替换
# sh ../patches/*.sh

# 第四步：覆盖 overlay
rsync -av ./overlay/ workspace/