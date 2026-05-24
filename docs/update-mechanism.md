# PackClaw 自动更新机制

## 功能入口

设置 → 软件更新 → 检查更新

## 流程

1. **检查更新**：`autoUpdater.checkForUpdates()` 请求 latest.yml 文件，对比本地版本号
2. **发现新版本**：侧栏 / 设置页显示"安装更新"按钮
3. **下载安装**：`autoUpdater.downloadUpdate()` 从 CDN 下载安装包
4. **自动重启安装**：`quitAndInstall()` 重启应用完成安装

## 相关地址

| 地址 | 用途 |
|---|---|
| `https://packclaw.cn/releases/latest-mac.yml` | macOS 检查更新版本信息 |
| `https://packclaw.cn/releases/latest.yml` | Windows 检查更新版本信息 |
| `https://packclaw.cn/releases/dev-mac.yml` | dev 通道 macOS 版本信息 |
| `https://packclaw.cn/releases/dev.yml` | dev 通道 Windows 版本信息 |
| `https://packclaw.cn/releases/PackClaw-{version}.{ext}` | 实际下载安装包 |

## 更新地址优先级

1. 环境变量 `PACKCLAW_UPDATE_URL`
2. `electron-builder.yml` 中的 `publish.url`（默认 `https://packclaw.cn/releases/`）

## 更新通道

- **stable**（默认）：拉取 `latest-mac.yml` / `latest.yml`
- **dev**：拉取 `dev-mac.yml` / `dev.yml`，由 `~/.openclaw/packclaw.config.json` 中的 `updateChannel: "dev"` 开启

## 定时检查

- 启动后延迟 **30 秒**首次检查
- 之后每 **4 小时**检查一次

## 关键代码文件

| 文件 | 职责 |
|---|---|
| `src/auto-updater.ts` | electron-updater 封装，检查 / 下载 / 安装 / 定时调度 |
| `src/update-banner-state.ts` | 侧栏更新状态机 |
| `src/main.ts:565-567` | IPC 注册（`app:check-updates` / `app:get-update-state` / `app:download-and-install-update`） |
| `src/preload.ts:12-14` | 渲染层 IPC 桥接 |
| `chat-ui/ui/src/ui/views/settings/tab-about.ts` | 设置页"软件更新"UI |
| `electron-builder.yml:39-41` | 发布配置（provider: generic, url: packclaw.cn） |
