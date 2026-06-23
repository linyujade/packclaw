# 06-about-page-improvements.sh — 修改说明

## 修改了什么 & 为什么

| 编号 | 文件 | 问题 | 修复 |
|---|---|---|---|
| **R37** | `tab-about.ts` | 软件更新页没有手动下载入口 | 新增"手动下载"卡片，链接用 `ipc.openExternal` 打开系统默认浏览器（颜色 `--accent` 红色） |
| **R38** | `i18n.ts` | 缺少"进入网站下载"i18n key | 添加 zh `"进入网站下载"` + en `"Go to website to download"` |
| **R39** | `app-render.ts` | 侧边栏"重新启动即可更新"点击后直接下载 | 改为 `openSettingsView(state, "about")` 跳转到设置→软件更新页 |

## R37 详情

在 `renderTabAbout` 的软件更新卡片之后、section 闭合 `</div>` 之前插入：

```typescript
<!-- Manual Download -->
<div class="oc-settings__card">
  <div class="oc-settings__card-title">${t("settings.about.manualDownload")}</div>
  <a style="color:var(--accent);font-size:13px;cursor:pointer"
     @click=${(e: Event) => { e.preventDefault(); ipc.openExternal("https://www.packclaw.cn/#download"); }}>
    ${t("settings.about.gotoWebsite")}
  </a>
</div>
```

关键点：
- 使用 `ipc.openExternal` 而非 `window.open` 或 `<a target="_blank">`，确保在系统默认浏览器中打开
- 颜色用 `var(--accent)`（红色主题色），与应用其他外链一致
- `manualDownload` i18n key 已在 R26（patch 04）中定义

## R39 详情

`handleApplyUpdate` 函数体从：

```typescript
const current = state.updateBannerState;
if (current.status !== "available") {
  return;
}
try {
  await window.packclaw?.downloadAndInstallUpdate?.();
} catch { ... }
```

改为：

```typescript
openSettingsView(state, "about");
```

这样用户点击侧边栏更新提示后，进入设置→软件更新页面，可以查看版本信息、选择下载更新、或通过手动下载链接获取。
