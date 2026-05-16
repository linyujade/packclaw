# AGENTS.md

Guidance for agentic coding agents working in this repository.

## Project Overview

PackClaw is a cross-platform Electron desktop app that wraps the openclaw gateway into a standalone installable package. Three-process architecture: Electron Main Process → Gateway child process (Node.js 22 + openclaw) → BrowserWindow (Lit Chat UI loaded via file://).

## Build Commands

```bash
npm run build              # Vite (chat-ui) + TypeScript → dist/
npm run build:chat         # Build Chat UI only (Lit + Vite)
npx tsc                    # Compile TypeScript only (after editing src/*.ts)
npm run build:chat         # Rebuild Chat UI (after editing chat-ui/ui/**)
npm run dev                # Run Electron in dev mode (does NOT rebuild!)
npm run dev:isolated       # Second dev instance with isolated port + state dir
npm run package:resources  # Download Node.js 22 + install openclaw from npm
npm run clean              # Remove all generated files (dist, resources/runtime, out)
```

**Critical:** `npm run dev` only runs `electron .` against existing `dist/` and `chat-ui/dist/`. You MUST rebuild manually before restarting Electron after editing source files.

## Lint / Typecheck

There is no linter configured. `tsc --noEmit` is the de facto type check:

```bash
npx tsc --noEmit           # Type check without emitting
```

Run this after making changes to verify correctness.

## Tests

Tests use the built-in `node:test` runner (primary) and vitest (secondary, only 4 files that need `vi.mock`). No `npm test` script exists.

### Run all tests

```bash
node --test src/**/*.test.ts
```

### Run a single test file

```bash
npx tsx --test src/analytics-events.test.ts           # node:test files
npx vitest run src/packclaw-config.test.ts             # vitest files
```

### Run a self-executing chat-ui test

```bash
npx tsx chat-ui/ui/src/ui/gateway.test.ts
```

### Test conventions

- Colocated `*.test.ts` files in `src/` (excluded from `tsconfig.json` build output)
- Flat `test("description")` calls — no `describe()`/`it()` nesting
- Test descriptions often in Chinese
- `node:assert/strict` for assertions: `assert.equal()`, `assert.deepEqual()`, `assert.ok()`, `assert.throws()`
- Manual dependency injection preferred over framework mocking — pass fake objects as function parameters
- Isolated temp dirs via `fs.mkdtempSync()` for filesystem tests, cleaned up in finally blocks

## Code Style

### Formatting

| Rule | Convention |
|------|-----------|
| Indentation | 2 spaces (no tabs) |
| Semicolons | Always |
| Quotes | Double quotes (`"electron"`, not `'electron'`) |
| Trailing commas | Yes, in multi-line arrays/objects/params |
| Braces | Same-line opening brace |
| Line length | ~100-120 chars max |

### Imports

Ordered in three groups, separated by blank lines:

1. **Node built-ins** — namespace imports for heavily used modules, destructured for single items
2. **Third-party packages** — named imports
3. **Local modules** — relative `./` imports, no path aliases

```ts
import * as fs from "fs";
import * as path from "path";
import { ChildProcess, spawn } from "child_process";

import { app, BrowserWindow } from "electron";

import { GatewayProcess } from "./gateway-process";
import * as log from "./logger";
```

- Source files import built-ins **without** `node:` prefix (`"fs"`, not `"node:fs"`)
- Test files import with `node:` prefix (`"node:test"`, `"node:assert/strict"`)
- No path aliases — all local imports use relative `./` paths

### Exports

- **Named exports only** — no `export default` anywhere in the codebase
- Functions, classes, types, and constants are individually named-exported
- Logger imported as namespace: `import * as log from "./logger"` (avoids collision with `console.log`)

### Naming Conventions

| Element | Style | Example |
|---------|-------|---------|
| Files/dirs | `kebab-case` | `gateway-process.ts`, `analytics-events.ts` |
| Test files | `<module>.test.ts` | `analytics-events.test.ts` |
| Classes | `PascalCase` | `GatewayProcess`, `FeedbackSSE` |
| Interfaces | `PascalCase` | `GatewayOptions`, `BrowserTarget` |
| Functions | `camelCase` | `resolveGatewayPort()`, `diagLog()` |
| Constants | `UPPER_SNAKE_CASE` | `DEFAULT_PORT`, `MAX_LOG_SIZE`, `HEALTH_TIMEOUT_MS` |
| Type aliases | `PascalCase` | `GatewayState`, `AnalyticsErrorType` |
| Boolean vars | `is/has/was` prefix | `isNoisyRendererConsoleMessage` |

### Types

- `strict: true` enabled in tsconfig — all code must pass strict type checking
- `type` for union types and simple shapes: `type GatewayState = "stopped" | "starting" | "running" | "stopping"`
- `interface` for objects with methods or structural contracts
- Explicit return types on exported functions: `export function info(msg: string): void`
- `readonly` on constant arrays: `export const BROWSER_TARGETS: readonly BrowserTarget[]`
- Nullable with explicit `| null`: `private proc: ChildProcess | null = null`
- `Record<string, any>` for loosely-typed config objects

### Async Patterns

- Exclusively `async/await` — no `.then()`/`.catch()` chains
- Polling via `await sleep(ms)` helper
- `Promise.race` for timeouts

### Error Handling

- Silent `catch {}` for non-critical operations (mkdir, JSON parse of optional files)
- Log before swallowing on important paths: `log.error(\`context: \${err.message}\`)`
- No custom error classes — errors classified via string matching for analytics
- Config reads wrapped in try/catch with sensible defaults as fallback

### Logging

Custom logger at `src/logger.ts` — no third-party logging library:

```ts
import * as log from "./logger";
log.info("message");
log.warn("message");
log.error("message");
```

- Dual-write: file (`~/.openclaw/app.log`) + console
- 5MB rotation with truncation
- Structured context via template strings: `` log.error(`[renderer:${label}] did-fail-load: code=${code}`) ``

### Comments and Language

- **No comments unless necessary** — this codebase uses minimal comments
- Bilingual: comments and test descriptions mix Chinese and English freely
- Section headers use Unicode box-drawing: `// ── Section Name ──`

## TypeScript Configuration

- Target: ES2022, Module: CommonJS (no ESM in main src)
- `strict: true`, `esModuleInterop: true`, `skipLibCheck: true`
- `declaration: false`, `sourceMap: false`
- Test files excluded from build via `tsconfig.json`

## Key Architecture Notes

- Gateway process is a state machine: `stopped→starting→running→stopping` with generation tracking
- Auth token injected into BrowserWindow via URL fragment `#token=...`
- Preload script exposes ~75 IPC methods via `contextBridge` (sandbox mode)
- Platform-aware code uses `IS_WIN` constant and `process.platform` checks
- Numeric separators for readability: `180_000`, `5 * 1024 * 1024`
- Nullish coalescing assignment for defaults: `config.gateway ??= {}`
