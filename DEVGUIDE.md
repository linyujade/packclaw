# 开发说明

## 前置要求

- Node.js >= 22.12.0

验证版本：

```bash
node --version
```

## 完整开发流程

### 1. 安装依赖

```bash
npm install
```

### 2. 类型检查

```bash
npx tsc --noEmit
```

### 3. 跑测试

```bash
# 跑全部 node:test 测试（src/ 下 21 个测试文件）
node --test src/**/*.test.ts

# 跑单个测试文件（node:test）
npx tsx --test src/analytics-events.test.ts

# 跑 vitest 测试（4 个文件）
npx vitest run src/packclaw-config.test.ts

# 跑自执行的 chat-ui 测试
npx tsx chat-ui/ui/src/ui/gateway.test.ts
```

### 4. 构建 + 本地运行验证

一键完成（安装依赖 → 下载资源 → 编译 → 启动 Electron）：

```bash
npm run dev
```

如果只是改了代码想重启，按需重新编译：

```bash
npx tsc                    # 只改了 src/*.ts
npm run build:chat         # 只改了 chat-ui
npm run build              # 两者都改了
npm run dev                # 启动
```

**注意：** `npm run dev` 只运行 `electron .`，不会自动重新编译。修改源码后必须手动编译再重启。

### 5. 打包发布

**打包前先改回生产配置：** `.env.build` 中 `PACKCLAW_GATEWAY_ASAR=1`（开发时改为 0，打包时必须改回 1，否则安装包体积巨大且启动慢）。

Windows cmd 不支持 `VAR=value command` 语法，`npm run dist:win:x64` 无法直接使用。需要分步执行：

```cmd
set PACKCLAW_TARGET=win32-x64
npm run build
npm run package:resources -- --platform win32 --arch x64
npx electron-builder --win --x64 --config.directories.output=out/win32-x64 --publish never
```

产物在 `out/win32-x64/` 下，是 NSIS 安装包。

## 开发 vs 打包配置切换

| 配置项 | 开发 (`npm run dev`) | 打包发布 |
|--------|---------------------|----------|
| `.env.build` PACKCLAW_GATEWAY_ASAR | `0`（散文件，dev 模式才能读） | `1`（单文件，启动快） |
| `package.json` packclaw.officecli | 可删除（跳过 GitHub 下载） | 保留（需 OfficeCLI 功能） |

开发时改完配置后需重新执行 `npm run package:resources` 使其生效。

## 总结

```
npm install → tsc --noEmit → node --test src/**/*.test.ts → npm run dev → 打包前切配置 → 分步打包
```

先跑通测试和本地运行，确认没问题再打包。
