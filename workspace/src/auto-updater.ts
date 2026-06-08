import { autoUpdater } from "electron-updater";
import { app, dialog, shell } from "electron";
import * as child_process from "child_process";
import * as fsSync from "fs";
import * as path from "path";
import * as log from "./logger";
import { readPackclawConfig } from "./packclaw-config";
import {
  canStartUpdateDownload,
  createInitialUpdateBannerState,
  reduceUpdateBannerState,
  type UpdateBannerState,
} from "./update-banner-state";

// ── 常量 ──

const CHECK_INTERVAL_MS = 4 * 60 * 60 * 1000; // 4 小时定时检查
const STARTUP_DELAY_MS = 30 * 1000;            // 启动后延迟 30 秒（避免与 gateway 启动争资源）

// ── 状态 ──

let isManualCheck = false;
let startupTimer: ReturnType<typeof setTimeout> | null = null;
let intervalTimer: ReturnType<typeof setInterval> | null = null;
let progressCallback: ((percent: number | null) => void) | null = null;
let beforeQuitForInstallCallback: (() => void) | null = null;
let updateBannerStateCallback: ((state: UpdateBannerState) => void) | null = null;
let updateBannerState = createInitialUpdateBannerState();
let downloadInFlight: Promise<boolean> | null = null;
let pendingUpdateFile: string | null = null;

// 统一格式化更新错误，避免日志出现 [object Object]
function formatUpdaterError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

function translateUpdateError(err: unknown): string {
  const msg = formatUpdaterError(err);
  if (msg.includes("ERR_UPDATER_CHANNEL_FILE_NOT_FOUND") || msg.includes("404") || msg.includes("Cannot find channel")) {
    return "暂无可用更新，更新服务正在部署中，请稍后再试。";
  }
  if (msg.includes("net::ERR_CONNECTION") || msg.includes("ECONNREFUSED") || msg.includes("ETIMEDOUT") || msg.includes("fetch failed")) {
    return "网络连接失败，请检查网络后重试。";
  }
  if (msg.includes("ERR_UPDATER_INVALID_VERSION")) {
    return "更新信息格式异常，请稍后再试。";
  }
  if (msg.includes("ERR_CHECKSUM_MISMATCH")) {
    return "更新文件校验失败，请重新检查更新。";
  }
  if (msg.includes("ERR_UPDATER_NO_CHECKSUM")) {
    return "更新文件信息不完整，请联系开发者。";
  }
  return msg;
}

let manualErrorHandled = false;

// 统一发布侧栏更新状态，保证主进程与渲染层状态一致。
function publishUpdateBannerState(
  event: Parameters<typeof reduceUpdateBannerState>[1],
): UpdateBannerState {
  updateBannerState = reduceUpdateBannerState(updateBannerState, event);
  updateBannerStateCallback?.({ ...updateBannerState });
  return updateBannerState;
}

// 初始化自动更新
export function setupAutoUpdater(): void {
  autoUpdater.autoDownload = false;
  autoUpdater.autoInstallOnAppQuit = true;

  // 更新通道：环境变量 > packclaw.config.json > 默认 latest
  // dev 通道拉取 dev-mac.yml / dev.yml（CI 构建完立即推送），stable 拉取 latest-mac.yml / latest.yml
  const envUrl = process.env.PACKCLAW_UPDATE_URL;
  if (envUrl) {
    log.info(`[updater] 使用自定义更新地址: ${envUrl}`);
    autoUpdater.setFeedURL({ provider: "generic", url: envUrl });
  } else {
    const channel = readPackclawConfig()?.updateChannel;
    if (channel === "dev") {
      log.info("[updater] 使用 dev 更新通道");
      autoUpdater.channel = "dev";
    }
  }

  // 将 electron-updater 内部日志转发到 app.log
  autoUpdater.logger = {
    info: (msg: unknown) => log.info(`[updater] ${msg}`),
    warn: (msg: unknown) => log.warn(`[updater] ${msg}`),
    error: (msg: unknown) => log.error(`[updater] ${msg}`),
  };

  autoUpdater.on("checking-for-update", () => {
    log.info("[updater] 正在检查更新...");
  });

  // 发现新版本后仅更新侧栏状态，不再弹窗打断用户流程。
  autoUpdater.on("update-available", (info) => {
    log.info(`[updater] 发现新版本 ${info.version}`);
    publishUpdateBannerState({
      type: "update-available",
      version: info.version,
    });
    isManualCheck = false;
  });

  // 已是最新版本
  autoUpdater.on("update-not-available", (info) => {
    log.info(`[updater] 已是最新版本 ${info.version}`);
    if (updateBannerState.status !== "downloading") {
      publishUpdateBannerState({ type: "update-not-available" });
    }
    if (isManualCheck) {
      void dialog.showMessageBox({
        type: "info",
        title: "检查更新",
        message: `当前已是最新版本 (${info.version})`,
      });
    }
    isManualCheck = false;
  });

  // 下载进度
  autoUpdater.on("download-progress", (progress) => {
    const normalizedPercent = Number.isFinite(progress.percent)
      ? Math.max(0, Math.min(100, progress.percent))
      : 0;
    const pct = normalizedPercent.toFixed(1);
    log.info(`[updater] 下载进度: ${pct}%`);
    progressCallback?.(normalizedPercent);
    publishUpdateBannerState({
      type: "download-progress",
      percent: normalizedPercent,
    });
  });

  // macOS: 下载完成后解压 zip，提取 .app 备用，点击"打开安装包"时直接复制到 /Applications 并重启。
  // Windows: 保持原有 quitAndInstall 行为（NSIS 自动安装正常）。
  autoUpdater.on("update-downloaded", (info) => {
    log.info("[updater] 更新下载完成");
    progressCallback?.(null);

    if (process.platform === "darwin") {
      try {
        const cacheDir = path.join(app.getPath("home"), "Library", "Caches", "packclaw-updater", "pending");
        const infoPath = path.join(cacheDir, "update-info.json");
        if (fsSync.existsSync(infoPath)) {
          const raw = fsSync.readFileSync(infoPath, "utf-8");
          const parsed = JSON.parse(raw);
          const srcZip = path.join(cacheDir, parsed.fileName);
          if (fsSync.existsSync(srcZip)) {
            const extractDir = path.join(cacheDir, "extracted");
            if (fsSync.existsSync(extractDir)) {
              fsSync.rmSync(extractDir, { recursive: true, force: true });
            }
            fsSync.mkdirSync(extractDir, { recursive: true });
            child_process.execSync(`unzip -o -q "${srcZip}" -d "${extractDir}"`);
            const entries = fsSync.readdirSync(extractDir);
            const appDir = entries.find((e) => e.endsWith(".app"));
            if (appDir) {
              pendingUpdateFile = path.join(extractDir, appDir);
              log.info(`[updater] 已解压安装包: ${pendingUpdateFile}`);
            } else {
              log.error("[updater] 解压后未找到 .app");
            }
          }
        }
      } catch (copyErr) {
        log.error(`[updater] 解压安装包失败: ${formatUpdaterError(copyErr)}`);
      }
      publishUpdateBannerState({ type: "download-ready" });
    } else {
      publishUpdateBannerState({ type: "download-finished" });
      log.info("[updater] 准备自动重启安装更新");
      beforeQuitForInstallCallback?.();
      autoUpdater.quitAndInstall(false, true);
    }
  });

  // 错误处理
  autoUpdater.on("error", (err) => {
    log.error(`[updater] 更新失败: ${err.message}`);
    progressCallback?.(null);
    if (updateBannerState.status === "downloading") {
      publishUpdateBannerState({ type: "download-failed" });
    }
    if (isManualCheck && !manualErrorHandled) {
      manualErrorHandled = true;
      void dialog.showMessageBox({
        type: "error",
        title: "检查更新失败",
        message: translateUpdateError(err),
      });
    }
    isManualCheck = false;
  });
}

// 检查更新（manual=true 时弹窗反馈"已是最新"或错误）
export function checkForUpdates(manual = false): void {
  isManualCheck = manual;
  manualErrorHandled = false;
  void autoUpdater.checkForUpdates().catch((err) => {
    log.error(`[updater] 检查更新调用失败: ${formatUpdaterError(err)}`);
    if (manual && !manualErrorHandled) {
      manualErrorHandled = true;
      void dialog.showMessageBox({
        type: "error",
        title: "检查更新失败",
        message: translateUpdateError(err),
      });
    }
    isManualCheck = false;
  });
}

// 用户在侧栏点击“重新启动即可更新”后才触发下载，下载完成自动重启安装。
export async function downloadAndInstallUpdate(): Promise<boolean> {
  if (!canStartUpdateDownload(updateBannerState)) {
    return false;
  }
  if (downloadInFlight) {
    return downloadInFlight;
  }

  publishUpdateBannerState({ type: "download-started" });
  downloadInFlight = autoUpdater
    .downloadUpdate()
    .then(() => true)
    .catch((err) => {
      log.error(`[updater] 下载更新触发失败: ${formatUpdaterError(err)}`);
      publishUpdateBannerState({ type: "download-failed" });
      return false;
    })
    .finally(() => {
      downloadInFlight = null;
    });
  return downloadInFlight;
}

// 启动定时检查（延迟首次 + 周期轮询）
export function startAutoCheckSchedule(): void {
  startupTimer = setTimeout(() => {
    checkForUpdates(false);
    intervalTimer = setInterval(() => checkForUpdates(false), CHECK_INTERVAL_MS);
  }, STARTUP_DELAY_MS);
}

// 停止定时检查
export function stopAutoCheckSchedule(): void {
  if (startupTimer) { clearTimeout(startupTimer); startupTimer = null; }
  if (intervalTimer) { clearInterval(intervalTimer); intervalTimer = null; }
}

// 注入下载进度回调（供 tray 显示 tooltip）
export function setProgressCallback(cb: (percent: number | null) => void): void {
  progressCallback = cb;
}

// 注入更新安装前回调（供主进程放行窗口关闭）
export function setBeforeQuitForInstallCallback(cb: () => void): void {
  beforeQuitForInstallCallback = cb;
}

// 注入侧栏更新状态回调（供主进程转发给渲染层）。
export function setUpdateBannerStateCallback(cb: (state: UpdateBannerState) => void): void {
  updateBannerStateCallback = cb;
  updateBannerStateCallback({ ...updateBannerState });
}

// 获取当前侧栏更新状态（供渲染层首屏同步）。
export function getUpdateBannerState(): UpdateBannerState {
  return { ...updateBannerState };
}


// macOS: 将已解压的 .app 复制到 /Applications 并重启。
// Windows: 不应走到这里（Windows 用 quitAndInstall）。
export async function openUpdateInstaller(): Promise<boolean> {
  if (!pendingUpdateFile) {
    log.warn("[updater] 没有已下载的安装包可打开");
    return false;
  }

  if (process.platform === "darwin") {
    try {
      const appName = path.basename(pendingUpdateFile);
      const destApp = `/Applications/${appName}`;
      log.info(`[updater] 开始安装: cp -R "${pendingUpdateFile}" "${destApp}"`);
      child_process.execSync(`cp -R "${pendingUpdateFile}" "${destApp}"`);
      log.info(`[updater] 安装完成，准备重启: ${destApp}`);
      publishUpdateBannerState({ type: "download-finished" });
      app.relaunch();
      app.exit(0);
      return true;
    } catch (err) {
      log.error(`[updater] 安装更新失败: ${formatUpdaterError(err)}`);
      return false;
    }
  }

  try {
    await shell.openPath(pendingUpdateFile);
    log.info(`[updater] 已打开安装包: ${pendingUpdateFile}`);
    publishUpdateBannerState({ type: "download-finished" });
    return true;
  } catch (err) {
    log.error(`[updater] 打开安装包失败: ${formatUpdaterError(err)}`);
    return false;
  }
}
