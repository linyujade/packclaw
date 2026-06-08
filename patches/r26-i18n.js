const fs = require("fs");
const f = process.argv[2];
let c = fs.readFileSync(f, "utf8");

// zh: add sidebar.updateReadyToInstall after sidebar.updateDownloading
c = c.replace(
  '"sidebar.updateDownloading": "正在下载更新 {percent}%",\n',
  '"sidebar.updateDownloading": "正在下载更新 {percent}%",\n    "sidebar.updateReadyToInstall": "点击打开安装包",\n'
);

// zh: add settings.about.openInstaller + manualDownload after settings.about.installUpdate
c = c.replace(
  '"settings.about.installUpdate": "安装并重启",\n',
  '"settings.about.installUpdate": "安装并重启",\n    "settings.about.openInstaller": "打开安装包",\n    "settings.about.manualDownload": "手动下载",\n'
);

// en: add sidebar.updateReadyToInstall after sidebar.updateDownloading
c = c.replace(
  '"sidebar.updateDownloading": "Downloading update {percent}%",\n',
  '"sidebar.updateDownloading": "Downloading update {percent}%",\n    "sidebar.updateReadyToInstall": "Open installer",\n'
);

// en: add settings.about.openInstaller + manualDownload after settings.about.installUpdate
c = c.replace(
  '"settings.about.installUpdate": "Install & Restart",\n',
  '"settings.about.installUpdate": "Install & Restart",\n    "settings.about.openInstaller": "Open Installer",\n    "settings.about.manualDownload": "Manual Download",\n'
);

fs.writeFileSync(f, c);
