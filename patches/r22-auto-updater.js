const fs = require("fs");
const f = process.argv[2];
let c = fs.readFileSync(f, "utf8");

// 1. Expand imports
c = c.replace(
  'import { dialog } from "electron";',
  'import { app, dialog, shell } from "electron";\nimport * as child_process from "child_process";\nimport * as fsSync from "fs";\nimport * as path from "path";'
);

// 2. Add pendingUpdateFile variable after downloadInFlight
c = c.replace(
  "let downloadInFlight: Promise<boolean> | null = null;",
  "let downloadInFlight: Promise<boolean> | null = null;\nlet pendingUpdateFile: string | null = null;"
);

// 3. Replace update-downloaded handler
c = c.replace(
  /  \/\/ 下载完成后直接重启安装，不再二次确认弹窗。\n  autoUpdater\.on\("update-downloaded", \(\) => \{[\s\S]*?autoUpdater\.quitAndInstall\(false, true\);\n  \}\);/,
  [
    '  // macOS: 下载完成后解压 zip，提取 .app 备用，点击"打开安装包"时直接复制到 /Applications 并重启。',
    "  // Windows: 保持原有 quitAndInstall 行为（NSIS 自动安装正常）。",
    '  autoUpdater.on("update-downloaded", (info) => {',
    '    log.info("[updater] 更新下载完成");',
    "    progressCallback?.(null);",
    "",
    "    if (process.platform === \"darwin\") {",
    "      try {",
    '        const cacheDir = path.join(app.getPath("home"), "Library", "Caches", "packclaw-updater", "pending");',
    '        const infoPath = path.join(cacheDir, "update-info.json");',
    "        if (fsSync.existsSync(infoPath)) {",
    '          const raw = fsSync.readFileSync(infoPath, "utf-8");',
    "          const parsed = JSON.parse(raw);",
    "          const srcZip = path.join(cacheDir, parsed.fileName);",
    "          if (fsSync.existsSync(srcZip)) {",
    '            const extractDir = path.join(cacheDir, "extracted");',
    "            if (fsSync.existsSync(extractDir)) {",
    "              fsSync.rmSync(extractDir, { recursive: true, force: true });",
    "            }",
    "            fsSync.mkdirSync(extractDir, { recursive: true });",
    '            child_process.execSync(`unzip -o -q "${srcZip}" -d "${extractDir}"`);',
    "            const entries = fsSync.readdirSync(extractDir);",
    '            const appDir = entries.find((e) => e.endsWith(".app"));',
    "            if (appDir) {",
    "              pendingUpdateFile = path.join(extractDir, appDir);",
    '              log.info(`[updater] 已解压安装包: ${pendingUpdateFile}`);',
    "            } else {",
    '              log.error("[updater] 解压后未找到 .app");',
    "            }",
    "          }",
    "        }",
    "      } catch (copyErr) {",
    '        log.error(`[updater] 解压安装包失败: ${formatUpdaterError(copyErr)}`);',
    "      }",
    '      publishUpdateBannerState({ type: "download-ready" });',
    "    } else {",
    '      publishUpdateBannerState({ type: "download-finished" });',
    '      log.info("[updater] 准备自动重启安装更新");',
    "      beforeQuitForInstallCallback?.();",
    "      autoUpdater.quitAndInstall(false, true);",
    "    }",
    "  });",
  ].join("\n")
);

// 4. Add openUpdateInstaller function at end of file
c += [
  "",
  "",
  "// macOS: 将已解压的 .app 复制到 /Applications 并重启。",
  "// Windows: 不应走到这里（Windows 用 quitAndInstall）。",
  "export async function openUpdateInstaller(): Promise<boolean> {",
  "  if (!pendingUpdateFile) {",
  '    log.warn("[updater] 没有已下载的安装包可打开");',
  "    return false;",
  "  }",
  "",
  '  if (process.platform === "darwin") {',
  "    try {",
  "      const appName = path.basename(pendingUpdateFile);",
  "      const destApp = `/Applications/${appName}`;",
  '      log.info(`[updater] 开始安装: cp -R "${pendingUpdateFile}" "${destApp}"`);',
  '      child_process.execSync(`cp -R "${pendingUpdateFile}" "${destApp}"`);',
  "      log.info(`[updater] 安装完成，准备重启: ${destApp}`);",
  '      publishUpdateBannerState({ type: "download-finished" });',
  "      app.relaunch();",
  "      app.exit(0);",
  "      return true;",
  "    } catch (err) {",
  "      log.error(`[updater] 安装更新失败: ${formatUpdaterError(err)}`);",
  "      return false;",
  "    }",
  "  }",
  "",
  "  try {",
  "    await shell.openPath(pendingUpdateFile);",
  "    log.info(`[updater] 已打开安装包: ${pendingUpdateFile}`);",
  '    publishUpdateBannerState({ type: "download-finished" });',
  "    return true;",
  "  } catch (err) {",
  "    log.error(`[updater] 打开安装包失败: ${formatUpdaterError(err)}`);",
  "    return false;",
  "  }",
  "}",
  "",
].join("\n");

fs.writeFileSync(f, c);
