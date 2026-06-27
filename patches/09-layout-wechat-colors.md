# Patch 09 — 大字号布局修复 + 微信配色 + 字体范围扩展

## R47: chat-main min-width
- **File:** `chat-ui/ui/src/styles.css`
- **Change:** `.chat-main { min-width: 400px }` → `min-width: 0`
- **Reason:** zoom 1.6 + 窗口 958px 时可用空间 381px < 400px 最小宽度，内容溢出被 `overflow: hidden` 裁剪。

## R48: card.chat padding
- **File:** `chat-ui/ui/src/styles.css`
- **Change:** `.packclaw-content>.card.chat` 加 `padding: 0`
- **Reason:** 去掉继承自 `.card` 的 20px padding，让消息区和输入框宽度完全一致。

## R49: chat-group-messages flex
- **File:** `chat-ui/ui/src/styles.css`
- **Change:** `max-width: min(900px, calc(100% - 60px))` → `min-width: 0; flex: 1`
- **Reason:** 去掉固定 max-width 限制，让消息容器和输入框一样撑满主区域宽度。

## R50: chat-bubble display
- **File:** `chat-ui/ui/src/styles.css`
- **Change:** `display: inline-block` → `display: block; width: auto`；`word-wrap: break-word` → `overflow-wrap: anywhere; word-break: break-word`
- **Reason:** `inline-block` 在 `row-reverse` flex 中有边界计算 bug，导致内容截断。

## R51: sidebar flex-shrink
- **File:** `chat-ui/ui/src/styles.css`
- **Change:** `.packclaw-sidebar__brand`、`.packclaw-sidebar__footer` 加 `flex-shrink: 0`；新增 `.packclaw-sidebar__nav > :not(.session-list) { flex-shrink: 0 }`
- **Reason:** 大字号时 sidebar 内容被压缩，只有会话列表区域应可滚动。

## R52: 微信风格配色（仅浅色主题）
- **File:** `chat-ui/ui/src/styles.css`
- **Change:**
  - AI 回复（非工具消息）：`background: #efefef; color: #1a1a1a; --chat-text: #1a1a1a`
  - 用户消息：`background: #95ec69; color: #1a1a1a; --chat-text: #1a1a1a`
  - 工具消息：保持原配色
  - 深色主题：保持原配色
- **Note:** `--chat-text` 变量必须覆盖，否则 `.chat-text` 子元素的 `color: var(--chat-text)` 会覆盖 bubble 上的 `color`。

## R53: 字体缩放范围扩展
- **Files:** `storage.ts`, `app-settings.ts`, `tab-appearance.ts`, `i18n.ts`, `main.ts`
- **Change:** clamp 范围 `0.85–1.3` → `0.85–2.2`；选项 `0.85/1.0/1.1/1.2` → `0.85/1.0/1.3/1.6/2.2`
- **Reason:** 用户需要更大字号选项（大/更大/超大）。
- **Note:** 此补丁兼容 patch 08 已应用的旧值，通过 `grep -q` 检测并替换。
