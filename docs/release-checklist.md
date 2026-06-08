# PackClaw 发布流程

## 快速发布（推荐）

使用 `scripts/publish.sh` 一键完成发布：

```bash
# 预览将执行的操作（不修改任何文件）
bash scripts/publish.sh --dry-run

# 只更新本地 yml + index.html，不上传服务器
bash scripts/publish.sh --skip-upload

# 完整发布（自动更新 yml、index.html、上传到服务器）
PACKCLAW_DEPLOY_SERVER=user@your-server bash scripts/publish.sh 1.0.2

# 版本号可省略，自动从 workspace/package.json 读取
PACKCLAW_DEPLOY_SERVER=user@your-server bash scripts/publish.sh
```

脚本会自动完成：
1. 检查 `workspace/out/` 下的打包产物是否齐全
2. 从 `out/*/latest*.yml` 提取 sha512/size，合并生成 `website/releases/` 下的 4 个 yml 文件（`latest-mac.yml`、`latest.yml`、`dev-mac.yml`、`dev.yml`）
3. 更新 `website/index.html` 中 4 个下载按钮的版本号
4. 上传所有文件到服务器（需设置 `PACKCLAW_DEPLOY_SERVER`）

### 环境变量

| 变量 | 说明 | 示例 |
|---|---|---|
| `PACKCLAW_DEPLOY_SERVER` | 服务器 SSH 地址 | `root@1.2.3.4` |
| `PACKCLAW_DEPLOY_PATH` | 服务器部署路径 | `/home/www-data/packclaw-web`（默认值） |

也可以写入 `.env` 或 shell profile 中持久化：

```bash
export PACKCLAW_DEPLOY_SERVER=root@1.2.3.4
export PACKCLAW_DEPLOY_PATH=/home/www-data/packclaw-web
```

### 命令行参数

| 参数 | 说明 |
|---|---|
| `版本号`（可选） | 指定发布版本，如 `1.0.2`。省略则从 `workspace/package.json` 读取 |
| `--dry-run` | 预览模式，只打印将执行的操作，不修改任何文件 |
| `--skip-upload` | 更新本地文件（yml + index.html），但不上传到服务器 |

---

## 手动发布流程

如果不使用脚本，可按以下步骤手动操作。

### 1. 打包

在 `workspace/` 下执行打包命令，生成各平台安装包到 `workspace/out/`：

```bash
cd workspace
npm run build
```

打包完成后，`workspace/out/` 下会出现：
- `darwin-arm64/` — macOS arm64（M 系列芯片）
- `darwin-x64/` — macOS Intel
- `win32-x64/` — Windows x64
- `win32-arm64/` — Windows ARM64

每个目录下会有 `.dmg`（mac）、`.zip`（mac 自动更新用）、`.exe`（win）、`latest*.yml` 等文件。

### 2. 更新 4 个 yml 文件

编辑 `website/releases/` 下的 4 个文件，更新版本号、sha512、size、releaseDate：

| 文件 | 用途 | 数据来源 |
|---|---|---|
| `latest-mac.yml` | macOS 正式频道自动更新 | 合并 `out/darwin-arm64/latest-mac.yml` + `out/darwin-x64/latest-mac.yml` |
| `latest.yml` | Windows 正式频道自动更新 | 合并 `out/win32-x64/latest.yml` + `out/win32-arm64/latest.yml` |
| `dev-mac.yml` | macOS 开发频道自动更新 | 内容同 `latest-mac.yml` |
| `dev.yml` | Windows 开发频道自动更新 | 内容同 `latest.yml` |

示例 `latest-mac.yml`：

```yaml
version: 1.0.2
files:
  - url: PackClaw-1.0.2-arm64-mac.zip
    sha512: <从 out/darwin-arm64/latest-mac.yml 复制>
    size: <从 out/darwin-arm64/latest-mac.yml 复制>
  - url: PackClaw-1.0.2-x64-mac.zip
    sha512: <从 out/darwin-x64/latest-mac.yml 复制>
    size: <从 out/darwin-x64/latest-mac.yml 复制>
releaseDate: '2026-06-05'
```

### 3. 更新官网下载链接

编辑 `website/index.html`，找到下载按钮区域（搜索 `dl-btn`），将 4 个链接中的版本号替换为新版本号：

```html
<a href="releases/PackClaw-{ver}-arm64.dmg" class="dl-btn" id="dl-mac-arm64">
<a href="releases/PackClaw-{ver}-x64.dmg" class="dl-btn" id="dl-mac-x64">
<a href="releases/PackClaw-Setup-{ver}-x64.exe" class="dl-btn" id="dl-win-x64">
<a href="releases/PackClaw-Setup-{ver}-arm64.exe" class="dl-btn" id="dl-win-arm64">
```

### 4. 上传到服务器

所有文件统一上传到服务器的 `releases/` 目录：

```bash
SERVER=user@your-server:/home/www-data/packclaw-web/
VERSION=1.0.2

# 安装包
scp workspace/out/darwin-arm64/PackClaw-${VERSION}-arm64.dmg ${SERVER}releases/
scp workspace/out/darwin-arm64/PackClaw-${VERSION}-arm64-mac.zip ${SERVER}releases/
scp workspace/out/darwin-x64/PackClaw-${VERSION}-x64.dmg ${SERVER}releases/
scp workspace/out/darwin-x64/PackClaw-${VERSION}-x64-mac.zip ${SERVER}releases/
scp workspace/out/win32-x64/PackClaw-Setup-${VERSION}-x64.exe ${SERVER}releases/
scp workspace/out/win32-arm64/PackClaw-Setup-${VERSION}-arm64.exe ${SERVER}releases/

# yml + index.html
scp website/releases/*.yml ${SERVER}releases/
scp website/index.html ${SERVER}
```

### 5. 清理旧版本（可选）

```bash
ssh user@your-server "rm /home/www-data/packclaw-web/releases/PackClaw-1.0.0*"
```

### 6. 验证

1. **自动更新检测**：打开已安装的 PackClaw → 设置 → 关于 → 检查更新，应能看到新版本
2. **macOS 更新流程**：点击更新 → 下载完成 → 提示"点击打开安装包" → 打开 DMG → 拖入 Applications
3. **Windows 更新流程**：点击更新 → 下载完成 → 自动重启安装
4. **官网下载**：访问 `https://packclaw.cn` → 点击下载按钮 → 文件正常下载
5. **yml 可访问**：访问 `https://packclaw.cn/releases/latest-mac.yml` 确认内容正确
