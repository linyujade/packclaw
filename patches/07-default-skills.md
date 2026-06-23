# 07-default-skills.sh — 修改说明

## 修改了什么 & 为什么

| 编号 | 文件 | 问题 | 修复 |
|---|---|---|---|
| **R40** | `src/main.ts` | 网关默认启用全部 22 个 bundled 技能，但多数用户只需要其中几个，多余技能占用 system prompt token | 启动时自动禁用 13 个非默认技能，只保留 9 个通用技能 |

## 默认启用的 9 个 bundled 技能

| 技能 | 用途 |
|---|---|
| openclaw-and-packclaw-manual | 产品文档查询 |
| officecli-docx | Word 文档创建/编辑 |
| officecli-pptx | PPT 幻灯片创建/编辑 |
| officecli-xlsx | Excel 表格创建/编辑 |
| weather | 天气查询 |
| clawhub | 技能商店搜索/安装 |
| coding-agent | 委托编码任务 |
| skill-creator | 创建/编辑技能 |
| session-logs | 会话日志搜索 |

## 默认禁用的 13 个 bundled 技能

`apple-notes`, `apple-reminders`, `camsnap`, `canvas`, `discord`, `github`, `healthcheck`, `imsg`, `model-usage`, `notion`, `peekaboo`, `tmux`, `video-frames`

## 实现细节

在 `main.ts` 中新增 `migrateDisableNonDefaultBundledSkills()` 函数：

1. 读 `openclaw.json`
2. 对 13 个技能逐个检查 `skills.entries[name]`：
   - 不存在 → 写入 `{ enabled: false }`
   - 存在但无 `enabled` 字段 → 补上 `enabled: false`
   - 已有 `enabled: true` → **跳过**（尊重用户手动启用）
   - 已有 `enabled: false` → 跳过
3. 有变更才写入，幂等

调用位置：两个启动路径（`case "packclaw"` 和 `case "legacy-packclaw"`），紧跟 `migrateDisableKimiClaw()` 之后。

## 注意事项

- 用户安装的 managed 技能（kimi-webbridge、skill-feishu-manager 等）不受影响，由各自的 `skills.entries` 单独控制
- 用户可在设置→技能页面手动启用被禁用的 bundled 技能，迁移函数不会覆盖已手动设置的值
- 如果上游新增 bundled 技能，该技能默认启用（不在 disable 列表中），需要手动加入 `NON_DEFAULT_BUNDLED_SKILLS` 数组
