#!/bin/bash
set -euo pipefail

# PackClaw 发布脚本
# 用法: bash scripts/publish.sh [版本号] [--skip-upload] [--dry-run]
# 示例: bash scripts/publish.sh 1.0.2
#        bash scripts/publish.sh --skip-upload   (只更新本地文件，不上传)
#        bash scripts/publish.sh --dry-run        (预览将执行的操作)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/workspace/out"
WEBSITE_DIR="$ROOT_DIR/website"
RELEASES_DIR="$WEBSITE_DIR/releases"
INDEX_HTML="$WEBSITE_DIR/index.html"

DEPLOY_SERVER="${PACKCLAW_DEPLOY_SERVER:-}"
DEPLOY_PATH="${PACKCLAW_DEPLOY_PATH:-/home/www-data/packclaw-web}"

# ─── 参数解析 ───
VERSION=""
SKIP_UPLOAD=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --skip-upload) SKIP_UPLOAD=true ;;
    --dry-run) DRY_RUN=true ;;
    -*) echo "未知选项: $arg"; exit 1 ;;
    *) VERSION="$arg" ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION="$(grep '"version"' "$ROOT_DIR/workspace/package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
  if [ -z "$VERSION" ]; then
    echo "错误: 无法从 package.json 获取版本号，请手动指定: bash scripts/publish.sh <版本号>"
    exit 1
  fi
fi

echo "========================================="
echo "  PackClaw 发布  v${VERSION}"
echo "========================================="

TODAY="$(date +%Y-%m-%d)"

info()  { echo "  [INFO]  $*"; }
warn()  { echo "  [WARN]  $*" >&2; }
error() { echo "  [ERROR] $*" >&2; exit 1; }
dry()   { echo "  [DRY]   $*"; }

# 从 electron-builder 生成的 yml 中提取 files 块的条目
# 输出格式: url<TAB>sha512<TAB>size (每行一个文件)
extract_yml_entries() {
  local yml_file="$1"
  awk 'BEGIN{in_files=0;url="";sha="";sz=""} /^files:/{in_files=1;next} in_files&&/^  - url:/{if(url!="")printf"%s\t%s\t%s\n",url,sha,sz;url=$0;sub(/^  - url: */,"",url);sha="";sz="";next} in_files&&/sha512:/{sha=$0;sub(/^ *sha512: */,"",sha);next} in_files&&/size:/{sz=$0;sub(/^ *size: */,"",sz);next} /^[^ ]/&&in_files{if(url!="")printf"%s\t%s\t%s\n",url,sha,sz;url="";in_files=0}' "$yml_file"
}


# ═══════════════════════════════════════════
# Step 1: 检查打包产物
# ═══════════════════════════════════════════
echo ""
echo "── Step 1: 检查打包产物 ──"

UPLOAD_FILES=()
check_file() {
  local f="$1"
  if [ -f "$f" ]; then
    info "✓ $(basename "$f")"
    UPLOAD_FILES+=("$f")
  else
    warn "✗ 缺少 $(basename "$f")"
  fi
}

for platform_dir in darwin-arm64 darwin-x64; do
  check_file "$OUT_DIR/$platform_dir/PackClaw-${VERSION}-${platform_dir#darwin-}-mac.zip"
  check_file "$OUT_DIR/$platform_dir/PackClaw-${VERSION}-${platform_dir#darwin-}.dmg"
done
for platform_dir in win32-x64 win32-arm64; do
  check_file "$OUT_DIR/$platform_dir/PackClaw-Setup-${VERSION}-${platform_dir#win32-}.exe"
done

if [ ${#UPLOAD_FILES[@]} -eq 0 ]; then
  error "没有找到任何打包产物，请先执行打包命令"
fi

# ═══════════════════════════════════════════
# Step 1.5: macOS ad-hoc 签名后处理
# ═══════════════════════════════════════════
echo ""
echo "── Step 1.5: macOS 签名后处理 ──"

for platform_dir in darwin-arm64 darwin-x64; do
  APP_PATH="$OUT_DIR/$platform_dir/mac-${platform_dir#darwin-}/PackClaw.app"
  DMG_PATH="$OUT_DIR/$platform_dir/PackClaw-${VERSION}-${platform_dir#darwin-}.dmg"
  if [ -d "$APP_PATH" ]; then
    if [ "$DRY_RUN" = true ]; then
      dry "codesign --force --deep --sign - $APP_PATH"
    else
      codesign --force --deep --sign - "$APP_PATH" 2>&1 | while IFS= read -r line; do
        warn "$line"
      done
      info "✓ ${platform_dir}: ad-hoc 重新签名完成"
    fi
  fi
  if [ -f "$DMG_PATH" ]; then
    if [ "$DRY_RUN" = true ]; then
      dry "xattr -cr $DMG_PATH"
    else
      xattr -cr "$DMG_PATH"
      info "✓ ${platform_dir}: DMG 隔离属性已清除"
    fi
  fi
done

# ═══════════════════════════════════════════
# Step 2: 生成 yml 文件
# ═══════════════════════════════════════════
echo ""
echo "── Step 2: 生成 yml 文件 ──"

generate_yml() {
  local output_file="$1"
  shift
  local sources=("$@")
  local combined=""

  for src in "${sources[@]}"; do
    if [ -f "$src" ]; then
      combined+="$(extract_yml_entries "$src")"$'\n'
    fi
  done

  if [ -z "$combined" ]; then
    warn "无数据，跳过 $(basename "$output_file")"
    return 1
  fi

  local content="version: ${VERSION}"$'\n'"files:"

  while IFS=$'\t' read -r url sha512 size; do
    [ -z "$url" ] && continue
    local entry=$'\n'"  - url: ${url}"
    entry+=$'\n'"    sha512: ${sha512}"
    if [ -n "$size" ]; then
      entry+=$'\n'"    size: ${size}"
    fi
    content+="$entry"
  done <<< "$combined"

  content+=$'\n'"releaseDate: '${TODAY}'"

  if [ "$DRY_RUN" = true ]; then
    dry "生成 $(basename "$output_file") (未写入)"
    return 0
  fi

  echo "$content" > "$output_file"
  info "✓ $(basename "$output_file")"
}

generate_yml "$RELEASES_DIR/latest-mac.yml" \
  "$OUT_DIR/darwin-arm64/latest-mac.yml" \
  "$OUT_DIR/darwin-x64/latest-mac.yml" || true

generate_yml "$RELEASES_DIR/dev-mac.yml" \
  "$OUT_DIR/darwin-arm64/latest-mac.yml" \
  "$OUT_DIR/darwin-x64/latest-mac.yml" || true

generate_yml "$RELEASES_DIR/latest.yml" \
  "$OUT_DIR/win32-x64/latest.yml" \
  "$OUT_DIR/win32-arm64/latest.yml" || true

generate_yml "$RELEASES_DIR/dev.yml" \
  "$OUT_DIR/win32-x64/latest.yml" \
  "$OUT_DIR/win32-arm64/latest.yml" || true

YML_FILES=(
  "$RELEASES_DIR/latest-mac.yml"
  "$RELEASES_DIR/latest.yml"
  "$RELEASES_DIR/dev-mac.yml"
  "$RELEASES_DIR/dev.yml"
)

# ═══════════════════════════════════════════
# Step 3: 更新 index.html 下载链接
# ═══════════════════════════════════════════
echo ""
echo "── Step 3: 更新 index.html 下载链接 ──"

if [ -f "$INDEX_HTML" ]; then
  if [ "$DRY_RUN" = true ]; then
    dry "替换 index.html 版本号 → ${VERSION}"
  else
    sed -i '' \
      -e 's|releases/PackClaw-[0-9.]*-arm64\.dmg|releases/PackClaw-'"${VERSION}"'-arm64.dmg|g' \
      -e 's|releases/PackClaw-[0-9.]*-x64\.dmg|releases/PackClaw-'"${VERSION}"'-x64.dmg|g' \
      -e 's|releases/PackClaw-Setup-[0-9.]*-x64\.exe|releases/PackClaw-Setup-'"${VERSION}"'-x64.exe|g' \
      -e 's|releases/PackClaw-Setup-[0-9.]*-arm64\.exe|releases/PackClaw-Setup-'"${VERSION}"'-arm64.exe|g' \
      "$INDEX_HTML"
    info "✓ index.html 版本号 → ${VERSION}"
  fi
else
  warn "index.html 不存在，跳过"
fi

# ═══════════════════════════════════════════
# Step 4: 上传到服务器
# ═══════════════════════════════════════════
echo ""
echo "── Step 4: 上传到服务器 ──"

if [ "$SKIP_UPLOAD" = true ]; then
  info "跳过上传 (--skip-upload)"
elif [ -z "$DEPLOY_SERVER" ]; then
  echo ""
  echo "  未设置 PACKCLAW_DEPLOY_SERVER，请通过环境变量指定服务器地址:"
  echo "    export PACKCLAW_DEPLOY_SERVER=user@your-server"
  echo "    bash scripts/publish.sh ${VERSION}"
  echo ""
  echo "  或直接 scp 上传以下文件:"
  echo ""
  echo "    # 安装包 → ${DEPLOY_PATH}/releases/"
  for f in "${UPLOAD_FILES[@]}"; do
    echo "    scp $f \${SERVER}:${DEPLOY_PATH}/releases/"
  done
  echo ""
  echo "    # yml + index.html"
  for f in "${YML_FILES[@]}"; do
    [ -f "$f" ] && echo "    scp $f \${SERVER}:${DEPLOY_PATH}/releases/"
  done
  echo "    scp ${INDEX_HTML} \${SERVER}:${DEPLOY_PATH}/"
  echo ""
else
  REMOTE="${DEPLOY_SERVER}:${DEPLOY_PATH}"

  ALL_REMOTE_NAMES=()
  for f in "${UPLOAD_FILES[@]}"; do ALL_REMOTE_NAMES+=("releases/$(basename "$f")"); done
  for f in "${YML_FILES[@]}"; do [ -f "$f" ] && ALL_REMOTE_NAMES+=("releases/$(basename "$f")"); done
  ALL_REMOTE_NAMES+=("index.html")

  CHECK_SCRIPT="for f in ${ALL_REMOTE_NAMES[*]}; do test -f \"${DEPLOY_PATH}/\$f\" && echo \"\$f\"; done"
  EXISTING_SET=()
  while IFS= read -r fname; do
    [ -n "$fname" ] && EXISTING_SET+=("$fname")
  done < <(ssh "$DEPLOY_SERVER" "$CHECK_SCRIPT" 2>/dev/null)

  is_existing() {
    local target="$1"
    for e in "${EXISTING_SET[@]}"; do
      [ "$e" = "$target" ] && return 0
    done
    return 1
  }

  overwrite_all=false

  upload_one() {
    local local_file="$1"
    local remote_rel="$2"
    local remote_dir="$3"
    local fname
    fname="$(basename "$local_file")"

    if is_existing "$remote_rel"; then
      if [ "$overwrite_all" = true ]; then
        : # 直接覆盖
      else
        echo ""
        echo -n "  服务器已存在 ${remote_rel}，覆盖? [y]es/[n]o/[a]ll/[q]uit: "
        read -r answer
        case "$answer" in
          [Aa]*) overwrite_all=true ;;
          [Yy]*) ;;
          [Qq]*) info "用户终止上传"; return 1 ;;
          *) info "  跳过 ${fname}"; return 0 ;;
        esac
      fi
    fi

    if [ "$DRY_RUN" = true ]; then
      dry "scp ${fname} → ${REMOTE}/${remote_dir}/"
    else
      scp "$local_file" "${REMOTE}/${remote_dir}/"
      info "  ✓ ${fname}"
    fi
    return 0
  }

  info "上传安装包到 ${REMOTE}/releases/ ..."
  for f in "${UPLOAD_FILES[@]}"; do
    upload_one "$f" "releases/$(basename "$f")" "releases" || break
  done

  info "上传 yml 文件..."
  for f in "${YML_FILES[@]}"; do
    [ -f "$f" ] || continue
    upload_one "$f" "releases/$(basename "$f")" "releases" || break
  done

  info "上传 index.html..."
  upload_one "$INDEX_HTML" "index.html" "" || true
fi

# ═══════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════
echo ""
echo "========================================="
echo "  发布完成!  v${VERSION}"
echo "========================================="
echo ""
echo "验证清单:"
echo "  [ ] 访问 https://packclaw.cn 检查下载链接"
echo "  [ ] 访问 https://packclaw.cn/releases/latest-mac.yml 检查版本号"
echo "  [ ] 打开 PackClaw → 设置 → 关于 → 检查更新"
echo ""
