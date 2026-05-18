# PackClaw — Custom OneClaw Distribution

## What This Repo Is

PackClaw is a meta-repo that forks [OneClaw](https://github.com/oneclaw/oneclaw) with custom branding and assets. It uses **git subtree + overlay** to track upstream and apply local customizations.

## Repository Structure

```
packclaw/
├── upstream/       # Git subtree of oneclaw/oneclaw (read-only, sync via scripts/run.sh)
├── workspace/      # Buildable project = upstream copy + overlay + patches
├── overlay/        # Files that override upstream (currently: custom app icons in assets/)
├── patches/        # Shell patches to apply after upstream copy (currently empty)
└── scripts/
    └── run.sh      # Sync: git subtree pull → copy upstream to workspace → rsync overlay
```

**All development and builds happen in `workspace/`.** That directory has its own `package.json`, `AGENTS.md`, `CLAUDE.md`, and full OneClaw source.

## Sync Workflow

```bash
bash scripts/run.sh
```

What `run.sh` does:
1. `git subtree pull --prefix=upstream oneclaw main --squash` — pull latest upstream
2. `rm -rf workspace && cp -r upstream workspace` — rebuild workspace from upstream
3. *(patches step is commented out)*
4. `rsync -av ./overlay/ workspace/` — apply local overrides

**After syncing, workspace is a clean copy of upstream + overlay. Any manual edits in workspace/ are lost on next sync.** Persistent changes must go into `overlay/` or `patches/`.

## Where to Work

| Task | Where |
|---|---|
| Edit OneClaw source code | `workspace/` (but changes are ephemeral — push to upstream instead) |
| Change branding / icons | `overlay/assets/` |
| Apply code patches | `patches/` (add shell scripts, uncomment in `run.sh`) |
| Run builds / dev server | `workspace/` (see `workspace/AGENTS.md`) |

## CI/CD

- **Trigger:** Push `v*` tag (e.g. `git tag v2026.318.0 && git push origin v2026.318.0`)
- **Builds:** 4 parallel jobs — macOS arm64, macOS x64, Windows x64, Windows arm64
- **Mac:** codesign + notarize (requires `CSC_LINK`, `APPLE_API_KEY` secrets)
- **Windows:** NSIS installer, kimi-claw pinned to 0.19.1 (flock/ftruncate compat)
- **Publish:** Binaries → Volcengine TOS (`packclaw-cn` bucket) → CDN at `packclaw.cn`
- **Release flow:** Build → upload binaries to TOS → create GitHub Release (draft) → publish draft → upload `latest*.yml` + refresh CDN
- **Dev channel:** `dev-mac.yml` / `dev.yml` generated alongside `latest*.yml` for `updateChannel: "dev"` users

### Version Scheme

Calendar-based: `YYYY.MMDD.N` from git tag. CI injects via `npm version` before build.

## Key Differences from Upstream OneClaw

- **CDN domain:** `packclaw.cn` (not `oneclaw.cn`)
- **App icons:** Custom icons in `overlay/assets/` (includes `critter-128.png`)
- **Gateway ASAR:** Enabled by default (`PACKCLAW_GATEWAY_ASAR=1`)
- **Telemetry/feedback:** Uses separate PackClaw secrets (`PACKCLAW_*`, `VOLCANO_*`)

## Further Reading

- `workspace/AGENTS.md` — Full OneClaw dev commands, architecture, design rules, gotchas
- `workspace/docs/gotchas.md` — 29 known gotchas
- `workspace/docs/architecture.md` — Per-module design docs
