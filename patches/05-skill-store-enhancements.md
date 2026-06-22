# 05-skill-store-enhancements.sh — 修改说明

> 本文件补充 `patches/05-skill-store-enhancements.sh` 的背景说明。
> 当补丁脚本因上游变更而失败时，配合 `patches/REQUIREMENTS.md` 的 R29–R36 逐条细节重新实现。

## 修改了什么 & 为什么

| 编号 | 文件 | 问题 | 修复 |
|---|---|---|---|
| **overlay** | `src/skill-store.ts` | 上游版本过于基础，缺少 450+ 行关键功能 | 全量覆盖（display names, store meta, frontmatter fix, 歧义 slug, 路径迁移等） |
| **R29** | `gateway-process.ts` | clawhub workdir 指向 `workspace/`，技能被标记为 `openclaw-workspace`，不在"已安装"显示 | workdir 改为 `~/.openclaw`，技能装到 `skills/` → `openclaw-managed` |
| **R30** | `preload.ts` | 渲染进程无法读取 displayName/meta 缓存 | 新增 `skillStoreGetDisplayNames` IPC |
| **R31** | `skill-store-view.ts` | 无法区分歧义 slug；卸载无 busy 状态；回调缺参数 | 新增 ownerHandle/ref 类型；卸载按钮显示"卸载中…"；回调传 version/downloads |
| **R32** | `app-render.ts` | 安装/卸载/搜索/显示多处问题 | 传完整参数；ref 匹配；搜索归一化分隔符；已安装卡片显示 displayName + version + downloads |
| **R33** | `controllers/skills.ts` | gateway 返回的技能缺少 displayName/version/downloads | loadSkills 时从 IPC 注入 |
| **R34** | `i18n.ts` | 缺少"卸载中"i18n key | 添加 zh + en |
| **R35** | `styles.css` | 卸载按钮禁用时无视觉反馈 | 添加 opacity:0.6 + cursor:not-allowed |
| **R36** | `package.json` | extract-zip 仅作为 electron 的间接依赖 | 显式声明 `^2.0.1` |

## skill-store.ts 全量覆盖说明

`skill-store.ts` 不走 patch 脚丁，而是通过 `overlay/src/skill-store.ts` 全量覆盖。原因：

- 上游版本 ~350 行，PackClaw 新增 ~450 行，改动率 > 120%
- 逐行 patch 极易因上游微调而失败，维护成本高于全量覆盖
- 上游该文件变动频率低（技能商店是 PackClaw 独有功能方向）

### overlay 版本包含的功能清单

| 功能 | 核心函数 | 解决的问题 |
|---|---|---|
| Display name 持久化 | `readDisplayNames` / `writeDisplayNames` / `putDisplayName` | 安装时存 registry displayName，同时以 slug 和 frontmatter name 为 key |
| Store meta 缓存 | `readStoreMeta` / `writeStoreMeta` / `putStoreMeta` | 持久化 version + downloads，已安装列表与商店列表元数据一致 |
| Frontmatter 修复 | `ensureFrontmatter` / `parseFrontmatterBlock` / `extractDescriptionFromBody` / `serializeFrontmatter` | 网关要求 `name` + `description` 同时存在，否则跳过该技能；第三方技能常缺 description |
| 歧义 slug 安装 | `manualInstallSkill` / `binaryGet` | 多作者同 slug 时 clawhub CLI 报 `AMBIGUOUS_SKILL_SLUG`，改用 API 直接下载 zip |
| ownerHandle 跟踪 | `saveOwnerHandle` in `installSkill` | 写入 `_meta.json`，构建 `@owner/slug` ref 供商店卡片匹配已安装状态 |
| 旧路径迁移 | `migrateLegacySkills` / `migrateLegacyClawhubLock` | 把 `~/.openclaw/workspace/skills/` 移到 `~/.openclaw/skills/` + 合并 lock.json |
| 启动时种子 meta | `seedStoreMetaFromLock` | 从 `lock.json` 回填版本号，已安装技能在启动时立即显示 version |
| 始终 --force 安装 | `installSkill` 使用 `["install", "--force", slug]` | 网关启用的技能卸载后可能残留目录，避免 "Already installed" 错误 |
| 卸载清理 | `uninstallSkill` 清除 displayNames + storeMeta + 容错 | 清理所有缓存；目录不存在或 "Not installed" 均视为成功 |
| 商店加载时回填 | `backfillDisplayNames` 同时写 displayNames 和 storeMeta | 商店列表加载时，为已安装技能自动补全元数据 |
| ref 格式的已安装列表 | `list-installed` IPC 返回 `@owner/slug` | 歧义 slug 卡片按 ref 精确匹配已安装状态 |
| install IPC 扩展 | `install` handler 接受 `version`, `downloads` | 安装时持久化元数据，无需额外请求 |

## 同步流程中的位置

```
pull-upstream.sh 执行顺序：
  01 rebrand
  02 customizations (R01–R17)
  03 caching (R18–R20)
  04 update installer (R21–R28)
  05 skill store enhancements (R29–R36)  ← 本补丁
  rsync overlay/  ← skill-store.ts 全量覆盖在此步生效
```

所有补丁均幂等（`grep -q` 检查是否已应用），重复运行安全。
