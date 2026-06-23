# PackClaw 内置技能清单与启用建议

> 最后更新：2026-06-23
> 数据来源：网关 `openclaw/skills/` 目录 + `~/.openclaw/openclaw.json` 配置

## 网关内置技能（bundled，22个）

| 技能 | 用途 | 平台 | 默认启用建议 |
|---|---|---|---|
| **openclaw-and-packclaw-manual** | 产品文档查询，用户问"怎么设置/配置"时查阅官方文档 | 全平台 | ✅ 启用 |
| **officecli-docx** | 创建/读取/编辑 Word 文档 | 全平台 | ✅ 启用 |
| **officecli-pptx** | 创建/读取/编辑 PPT 幻灯片 | 全平台 | ✅ 启用 |
| **officecli-xlsx** | 创建/读取/编辑 Excel 表格 | 全平台 | ✅ 启用 |
| **weather** | 天气查询（wttr.in / Open-Meteo） | 全平台 | ✅ 启用 |
| **clawhub** | 搜索/安装/发布技能（技能商店 CLI） | 全平台 | ✅ 启用 |
| **coding-agent** | 委托编码任务给 Codex/Claude Code | 全平台 | ✅ 启用 |
| **skill-creator** | 创建/编辑/审计 Agent 技能 | 全平台 | ✅ 启用 |
| **session-logs** | 搜索/分析历史会话日志 | 全平台 | ✅ 启用 |
| **canvas** | 在连接的设备上展示 HTML 内容 | 全平台 | 可选 |
| **video-frames** | 从视频提取帧/片段（需 ffmpeg） | 全平台 | 可选 |
| **github** | GitHub 操作（issues/PR/CI，需 gh CLI） | 全平台 | 可选 |
| **notion** | Notion 页面/数据库操作（需 API key） | 全平台 | 可选 |
| **tmux** | 远程控制 tmux 会话 | 全平台 | 可选 |
| **model-usage** | 模型用量/成本统计 | 全平台 | 可选 |
| **healthcheck** | 安全审计/系统加固检查 | 全平台 | 可选 |
| **apple-notes** | Apple 备忘录管理（需 memo CLI） | macOS only | 看需求 |
| **apple-reminders** | Apple 提醒事项管理（需 remindctl） | macOS only | 看需求 |
| **peekaboo** | macOS UI 截图/自动化 | macOS only | 看需求 |
| **imsg** | iMessage/短信收发 | macOS only | 看需求 |
| **camsnap** | RTSP/ONVIF 摄像头抓帧 | 全平台 | 看需求 |
| **discord** | Discord 消息操作（需 token） | 全平台 | 看需求 |

## 用户安装技能（managed）

这些技能通过技能商店安装，存放在 `~/.openclaw/skills/`。

| 技能 | 用途 | 来源 |
|---|---|---|
| **kimi-webbridge** | 浏览器自动化（控制真实浏览器） | PackClaw 内置 |
| **skill-feishu-manager** | 飞书文档/知识库/多维表格管理 | clawhub 商店 |

## 不需要全部启用

内置技能不需要全部启用，原因：

1. **平台限制**：apple-notes、apple-reminders、peekaboo、imsg 只在 macOS 有效，Windows 用户启用了也无意义
2. **依赖缺失**：github 需要 `gh` CLI，notion 需要 API key，discord 需要 token — 没配置的技能启用后会报"missing requirements"
3. **网关自动判断**：网关的 `eligible` 机制会自动检查依赖（`missing.bins`、`missing.env`、`missing.config`），不满足的技能即使 enabled 也不会被模型调用

建议默认只启用前 9 个通用技能（表格中标 ✅ 的），其余按需开启。

## 技能目录说明

| 目录 | source 标签 | 说明 |
|---|---|---|
| `openclaw/skills/` | `openclaw-bundled` | 网关内置，随 openclaw npm 包发布 |
| `~/.openclaw/skills/` | `openclaw-managed` | 用户通过技能商店安装 |
| `~/.openclaw/workspace/skills/` | `openclaw-workspace` | 旧路径（已迁移到 managed） |
| `~/.openclaw/agents/*/skills/` | `agents-personal` / `agents-project` | Agent 级别个人/项目技能 |

"已安装技能"分组只显示 source 为 `openclaw-managed` 的技能。
