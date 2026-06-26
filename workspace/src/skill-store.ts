import { app, ipcMain } from "electron";
import {
  resolveUserStateDir,
  resolveUserBinDir,
  resolveNodeBin,
  resolveNodeExtraEnv,
  resolveClawhubEntry,
  IS_WIN,
} from "./constants";
import { execFile } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as https from "https";
import * as http from "http";
import extractZip from "extract-zip";
import * as log from "./logger";
import { readPackclawConfig, writePackclawConfig } from "./packclaw-config";
import { readBuildConfigClawhubRegistry } from "./build-config";

// 构建时通过 build-config.json 注入的默认 registry，未配置则回退硬编码值
const DEFAULT_REGISTRY = readBuildConfigClawhubRegistry() || "https://clawhub.ai";
const FETCH_TIMEOUT_MS = 15_000;
const SKILL_STORE_CONFIG = "skill-store.json";

// 开发模式下打印网络请求日志
const debugLog = (msg: string) => {
  if (!app.isPackaged) log.info(`[skill-store] ${msg}`);
};

// ── 类型定义 ──

export type SkillSummary = {
  slug: string;
  name: string;
  description: string;
  version: string;
  downloads: number;
  highlighted: boolean;
  updatedAt: string;
  author: string;
  ownerHandle: string;
  ref: string;
};

export type SkillDetail = SkillSummary & {
  readme: string;
  author: string;
  tags: string[];
};

type ListResult = {
  skills: SkillSummary[];
  nextCursor: string | null;
};

// ── 独立配置文件读写（不污染 gateway 的 openclaw.json） ──

// 技能商店配置文件路径：~/.openclaw/skill-store.json
function skillStoreConfigPath(): string {
  return path.join(resolveUserStateDir(), SKILL_STORE_CONFIG);
}

// 读取 legacy 技能商店独立配置（兼容旧版 skill-store.json）
function readLegacySkillStoreConfig(): Record<string, any> {
  try {
    return JSON.parse(fs.readFileSync(skillStoreConfigPath(), "utf-8"));
  } catch {
    return {};
  }
}

// 写入 legacy 技能商店独立配置（兼容旧版 skill-store.json）
function writeLegacySkillStoreConfig(data: Record<string, any>): void {
  fs.mkdirSync(path.dirname(skillStoreConfigPath()), { recursive: true });
  fs.writeFileSync(skillStoreConfigPath(), JSON.stringify(data, null, 2) + "\n", "utf-8");
}

// ── Registry URL 公开接口（供 settings-ipc 使用） ──

// 读取 registry URL（优先 packclaw.config.json，兼容 legacy skill-store.json）
export function readSkillStoreRegistry(): string {
  const packclawConfig = readPackclawConfig();
  if (packclawConfig?.skillStore?.registryUrl) {
    return packclawConfig.skillStore.registryUrl;
  }
  const legacy = readLegacySkillStoreConfig();
  return typeof legacy?.registryUrl === "string" ? legacy.registryUrl : "";
}

// 写入 registry URL（写到 packclaw.config.json + legacy 文件双写）
export function writeSkillStoreRegistry(url: string): void {
  const config = readPackclawConfig();
  if (config) {
    if (url) {
      config.skillStore ??= {};
      config.skillStore.registryUrl = url;
    } else {
      delete config.skillStore?.registryUrl;
    }
    writePackclawConfig(config);
  }
  // legacy 文件双写保持兼容
  const legacyConfig = readLegacySkillStoreConfig();
  if (url) {
    legacyConfig.registryUrl = url;
  } else {
    delete legacyConfig.registryUrl;
  }
  writeLegacySkillStoreConfig(legacyConfig);
}

// ── Registry URL 解析 ──

// 读取用户自定义 registry 地址，未配置时回退官方默认值
function registryUrl(): string {
  const custom = readSkillStoreRegistry();
  if (custom.trim()) {
    return custom.trim().replace(/\/+$/, "");
  }
  return DEFAULT_REGISTRY;
}

// ── HTTP 请求封装 ──

// 通用 JSON GET 请求，带超时控制
function jsonGet<T>(url: string): Promise<T> {
  debugLog(`GET ${url}`);
  const startMs = Date.now();
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const mod = parsed.protocol === "https:" ? https : http;
    const req = mod.get(url, { timeout: FETCH_TIMEOUT_MS }, (res) => {
      if (res.statusCode && (res.statusCode < 200 || res.statusCode >= 300)) {
        debugLog(`GET ${url} → ${res.statusCode} (${Date.now() - startMs}ms)`);
        res.resume();
        reject(new Error(`HTTP ${res.statusCode}`));
        return;
      }
      const chunks: Buffer[] = [];
      res.on("data", (chunk: Buffer) => chunks.push(chunk));
      res.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf-8");
        debugLog(`GET ${url} → ${res.statusCode} ${body.length}B (${Date.now() - startMs}ms)\n${body}`);
        try {
          resolve(JSON.parse(body) as T);
        } catch (err) {
          debugLog(`GET ${url} → JSON parse error: ${err}`);
          reject(err);
        }
      });
    });
    req.on("error", (err) => {
      debugLog(`GET ${url} → error: ${err.message} (${Date.now() - startMs}ms)`);
      reject(err);
    });
    req.on("timeout", () => {
      debugLog(`GET ${url} → timeout (${Date.now() - startMs}ms)`);
      req.destroy();
      reject(new Error("request timeout"));
    });
  });
}

// ── API 响应 → 前端类型映射 ──

// 将 API 返回的原始条目转为前端 SkillSummary
function mapItem(raw: any): SkillSummary {
  const slug = raw.slug ?? "";
  const ownerHandle = raw.ownerHandle ?? raw.owner?.handle ?? "";
  return {
    slug,
    name: raw.displayName ?? slug ?? "",
    description: raw.summary ?? "",
    version: raw.tags?.latest ?? raw.latestVersion?.version ?? raw.version ?? "",
    downloads: raw.stats?.downloads ?? raw.downloads ?? 0,
    highlighted: true,
    updatedAt: raw.updatedAt ? new Date(raw.updatedAt).toISOString() : "",
    author: ownerHandle || (raw.author ?? raw.owner ?? ""),
    ownerHandle,
    ref: ownerHandle ? `@${ownerHandle}/${slug}` : slug,
  };
}

// ── 商店元数据缓存（slug → {version, downloads}）──

// 持久化 registry 返回的版本号和下载量，供"已安装"列表与商店列表显示一致的元数据
type StoreMeta = { version?: string; downloads?: number };

function storeMetaPath(): string {
  return path.join(resolveUserStateDir(), "skill-store-meta.json");
}

function readStoreMeta(): Record<string, StoreMeta> {
  try {
    return JSON.parse(fs.readFileSync(storeMetaPath(), "utf-8"));
  } catch {
    return {};
  }
}

function writeStoreMeta(map: Record<string, StoreMeta>): void {
  try {
    fs.mkdirSync(path.dirname(storeMetaPath()), { recursive: true });
    fs.writeFileSync(storeMetaPath(), JSON.stringify(map, null, 2) + "\n", "utf-8");
  } catch (err: any) {
    debugLog(`writeStoreMeta failed: ${err?.message ?? err}`);
  }
}

// 写入 store meta，同时以 slug 和 frontmatter name 为 key（与 putDisplayName 同理）
function putStoreMeta(map: Record<string, StoreMeta>, slug: string, version?: string, downloads?: number): void {
  const meta: StoreMeta = {};
  if (version) meta.version = version;
  if (downloads !== undefined && downloads > 0) meta.downloads = downloads;
  if (Object.keys(meta).length === 0) return;
  map[slug] = meta;
  const fmName = readFrontmatterName(slug);
  if (fmName && fmName !== slug) {
    map[fmName] = meta;
  }
}

// ── API 调用 ──

// 将 registry 返回的技能列表中已安装项的 displayName + version + downloads 回写到本地缓存
// 覆盖旧版本安装的技能（安装时未持久化这些字段的情况）
function backfillDisplayNames(skills: SkillSummary[]): void {
  const installed = new Set(listInstalledSkills());
  if (installed.size === 0) return;
  const dnMap = readDisplayNames();
  const metaMap = readStoreMeta();
  let dnChanged = false;
  let metaChanged = false;
  for (const s of skills) {
    if (!installed.has(s.slug)) continue;
    if (s.name && s.name !== s.slug) {
      const before = Object.keys(dnMap).length;
      putDisplayName(dnMap, s.slug, s.name);
      if (Object.keys(dnMap).length > before) dnChanged = true;
    }
    if (s.version || s.downloads) {
      const before = Object.keys(metaMap).length;
      putStoreMeta(metaMap, s.slug, s.version, s.downloads);
      if (Object.keys(metaMap).length > before) metaChanged = true;
    }
  }
  if (dnChanged) {
    writeDisplayNames(dnMap);
    debugLog(`backfill displayNames: ${Object.keys(dnMap).length} entries`);
  }
  if (metaChanged) {
    writeStoreMeta(metaMap);
    debugLog(`backfill storeMeta: ${Object.keys(metaMap).length} entries`);
  }
}

// 获取精选技能列表（分页）
async function listSkills(opts: {
  sort?: string;
  limit?: number;
  cursor?: string;
}): Promise<ListResult> {
  const base = registryUrl();
  const params = new URLSearchParams();
  params.set("highlightedOnly", "true");
  if (opts.sort) params.set("sort", opts.sort);
  if (opts.limit) params.set("limit", String(opts.limit));
  if (opts.cursor) params.set("cursor", opts.cursor);
  const raw = await jsonGet<any>(`${base}/api/v1/skills?${params}`);
  const items = Array.isArray(raw.items) ? raw.items : Array.isArray(raw.skills) ? raw.skills : [];
  const skills = items.map(mapItem);
  backfillDisplayNames(skills);
  return {
    skills,
    nextCursor: raw.nextCursor ?? null,
  };
}

// 搜索技能（不限 highlighted，搜全量）
async function searchSkills(opts: {
  q: string;
  limit?: number;
}): Promise<{ skills: SkillSummary[] }> {
  const base = registryUrl();
  const params = new URLSearchParams();
  params.set("q", opts.q);
  if (opts.limit) params.set("limit", String(opts.limit));
  const raw = await jsonGet<any>(`${base}/api/v1/search?${params}`);
  // 搜索接口返回 results 数组，兼容 items/skills 回退
  const items = Array.isArray(raw.results) ? raw.results : Array.isArray(raw.items) ? raw.items : [];
  const skills = items.map(mapItem);
  backfillDisplayNames(skills);
  return { skills };
}

// 获取技能详情
async function getSkillDetail(slug: string): Promise<SkillDetail> {
  const base = registryUrl();
  const raw = await jsonGet<any>(`${base}/api/v1/skills/${encodeURIComponent(slug)}`);
  return {
    ...mapItem(raw),
    readme: raw.readme ?? "",
    author: raw.author ?? raw.owner ?? "",
    tags: Array.isArray(raw.tagsList) ? raw.tagsList : [],
  };
}

// ── 展示名映射（slug → displayName）──

// 持久化 registry 返回的 displayName，供"已安装"列表显示友好名称
// 网关 skills.status 只返回 SKILL.md frontmatter 的 name（slug 风格），
// 而商店列表的 displayName（如 "Stock Watcher"）更友好，安装时存下来
function displayNamesPath(): string {
  return path.join(resolveUserStateDir(), "skill-display-names.json");
}

function readDisplayNames(): Record<string, string> {
  try {
    return JSON.parse(fs.readFileSync(displayNamesPath(), "utf-8"));
  } catch {
    return {};
  }
}

function writeDisplayNames(map: Record<string, string>): void {
  try {
    fs.mkdirSync(path.dirname(displayNamesPath()), { recursive: true });
    fs.writeFileSync(displayNamesPath(), JSON.stringify(map, null, 2) + "\n", "utf-8");
  } catch (err: any) {
    debugLog(`writeDisplayNames failed: ${err?.message ?? err}`);
  }
}

// 读取技能 SKILL.md frontmatter 的 name 字段
// skills.status 返回的 name 来自 frontmatter（如 "browser"），可能和目录名/slug（"browser-automation"）不同
// displayName 需要同时以 slug 和 frontmatter name 为 key 存储，确保查找时都能命中
function readFrontmatterName(slug: string): string | null {
  try {
    const md = fs.readFileSync(path.join(skillsBaseDir(), slug, "SKILL.md"), "utf-8");
    const fm = md.match(/^name:\s*["']?(.+?)["']?\s*$/m);
    return fm ? fm[1].trim() : null;
  } catch {
    return null;
  }
}

// 写入 displayName 映射，同时以 slug 和 frontmatter name 为 key
function putDisplayName(map: Record<string, string>, slug: string, displayName: string): void {
  map[slug] = displayName;
  const fmName = readFrontmatterName(slug);
  if (fmName && fmName !== slug) {
    map[fmName] = displayName;
  }
}

// 安装技能后：如果目录下有 requirements.txt，自动 pip3 install
function pipInstallRequirements(slug: string): void {
  const reqPath = path.join(skillsBaseDir(), slug, "requirements.txt");
  if (!fs.existsSync(reqPath)) return;
  try {
    const content = fs.readFileSync(reqPath, "utf-8").trim();
    if (!content) return;
    debugLog(`pipInstallRequirements: ${slug} has requirements.txt, installing...`);
    const pipBin = IS_WIN ? "pip3" : "pip3";
    execFile(pipBin, ["install", "-r", reqPath, "--quiet", "--disable-pip-version-check"], {
      timeout: 120_000,
      windowsHide: true,
      env: { ...process.env },
    }, (err, _stdout, stderr) => {
      if (err) {
        debugLog(`pipInstallRequirements: FAILED for ${slug}: ${err.message}`);
      } else {
        debugLog(`pipInstallRequirements: OK for ${slug}`);
      }
      if (stderr) debugLog(`pip stderr: ${stderr.toString().trim().slice(0, 500)}`);
    });
  } catch { /* non-critical */ }
}

// 确保技能 SKILL.md 有 YAML frontmatter（含 name + description 字段）
// 网关 loadSingleSkillDirectory 要求 frontmatter 同时包含 name 和 description，否则跳过该技能
function ensureFrontmatter(slug: string): void {
  const mdPath = path.join(skillsBaseDir(), slug, "SKILL.md");
  try {
    const md = fs.readFileSync(mdPath, "utf-8");
    const fm = parseFrontmatterBlock(md);
    if (fm) {
      let changed = false;
      if (!fm.name) { fm.name = slug; changed = true; }
      if (!fm.description) {
        fm.description = extractDescriptionFromBody(md) ?? slug;
        changed = true;
      }
      if (!changed) return;
      const patched = `---\n${serializeFrontmatter(fm)}---\n\n${fm.body}`;
      fs.writeFileSync(mdPath, patched, "utf-8");
      debugLog(`ensureFrontmatter: patched ${slug} (added missing fields)`);
    } else {
      const desc = extractDescriptionFromBody(md) ?? slug;
      const patched = `---\nname: ${slug}\ndescription: ${desc}\n---\n\n${md}`;
      fs.writeFileSync(mdPath, patched, "utf-8");
      debugLog(`ensureFrontmatter: patched ${slug} (no frontmatter found)`);
    }
  } catch { /* SKILL.md not found, skip */ }
}

// 解析 YAML frontmatter 块，返回 { name?, description?, body } 或 null
function parseFrontmatterBlock(md: string): { name?: string; description?: string; body: string } | null {
  if (!md.startsWith("---")) return null;
  const end = md.indexOf("\n---", 3);
  if (end === -1) return null;
  const block = md.slice(3, end);
  const body = md.slice(end + 4).replace(/^\n/, "");
  const result: { name?: string; description?: string; body: string } = { body };
  for (const line of block.split("\n")) {
    const m = line.match(/^(\w+):\s*(.+)$/);
    if (!m) continue;
    if (m[1] === "name") result.name = m[2].trim();
    else if (m[1] === "description") {
      result.description = m[2].trim().startsWith("|") ? undefined : m[2].trim();
    }
  }
  return result;
}

// 从 markdown body 提取第一段有意义的内容作为 description
function extractDescriptionFromBody(md: string): string | null {
  const fm = md.startsWith("---") ? (md.indexOf("\n---", 3) !== -1 ? md.slice(md.indexOf("\n---", 3) + 4) : md) : md;
  for (const line of fm.split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#") || t.startsWith("---")) continue;
    return t.replace(/[*`]/g, "").slice(0, 200);
  }
  return null;
}

// 将 frontmatter 对象序列化为 YAML 字符串（仅支持 name + description 等简单字段）
function serializeFrontmatter(fm: { name?: string; description?: string }): string {
  const lines: string[] = [];
  if (fm.name) lines.push(`name: ${fm.name}`);
  if (fm.description) {
    const needsBlock = fm.description.includes("\n") || fm.description.includes(":") || fm.description.length > 120;
    if (needsBlock) lines.push(`description: |\n  ${fm.description.replace(/\n/g, "\n  ")}`);
    else lines.push(`description: ${fm.description}`);
  }
  return lines.length > 0 ? lines.join("\n") + "\n" : "";
}

// ── clawhub CLI 调用 ──

// clawhub 安装技能的工作根目录：~/.openclaw
// （与网关 openclaw-managed 目录对齐：resolve(workdir, "skills") → ~/.openclaw/skills）
function skillsWorkdir(): string {
  return resolveUserStateDir();
}

// 技能安装根目录：~/.openclaw/skills/
// 网关 loadSkillEntries 把此目录的技能标记为 source="openclaw-managed" → "已安装技能"分组
function skillsBaseDir(): string {
  return path.join(skillsWorkdir(), "skills");
}

// 一次性迁移：把旧路径 ~/.openclaw/workspace/skills/ 下的技能移到新路径 ~/.openclaw/skills/
// 旧版本 clawhub --workdir 指向 workspace，技能被标记为 openclaw-workspace，无法出现在"已安装技能"分组
function migrateLegacySkills(): void {
  const legacyBase = path.join(resolveUserStateDir(), "workspace", "skills");
  const newBase = skillsBaseDir();
  if (!fs.existsSync(legacyBase)) return;
  let entries: string[];
  try {
    entries = fs.readdirSync(legacyBase);
  } catch {
    return;
  }
  let moved = 0;
  for (const name of entries) {
    const legacyDir = path.join(legacyBase, name);
    const newDir = path.join(newBase, name);
    try {
      if (!fs.statSync(legacyDir).isDirectory()) continue;
      if (!fs.existsSync(path.join(legacyDir, "SKILL.md"))) continue;
      if (fs.existsSync(newDir)) continue;
      fs.mkdirSync(newBase, { recursive: true });
      fs.renameSync(legacyDir, newDir);
      moved++;
      debugLog(`migrate skill: ${name} workspace/skills → skills`);
    } catch (err: any) {
      debugLog(`migrate skill skip ${name}: ${err?.message ?? err}`);
    }
  }
  if (moved > 0) debugLog(`migrate legacy skills: ${moved} moved`);

  // 同步迁移 clawhub 安装清单（lock.json），否则卸载时报 "Not installed"
  // 旧 workdir=~/.openclaw/workspace → 旧清单在 workspace/.clawhub/lock.json
  // 新 workdir=~/.openclaw       → 新清单在 .clawhub/lock.json
  migrateLegacyClawhubLock();
}

// 把旧 workdir 的 clawhub lock.json 合并到新 workdir
function migrateLegacyClawhubLock(): void {
  const legacyLockPath = path.join(resolveUserStateDir(), "workspace", ".clawhub", "lock.json");
  const newLockDir = path.join(skillsWorkdir(), ".clawhub");
  const newLockPath = path.join(newLockDir, "lock.json");
  let legacy: { version?: number; skills?: Record<string, any> } | null = null;
  try {
    legacy = JSON.parse(fs.readFileSync(legacyLockPath, "utf-8"));
  } catch {
    return; // 旧清单不存在，无需迁移
  }
  let next: { version?: number; skills?: Record<string, any> } = { version: 1, skills: {} };
  try {
    next = JSON.parse(fs.readFileSync(newLockPath, "utf-8"));
  } catch { /* 新清单不存在，用空模板 */ }
  next.skills ??= {};
  let added = 0;
  for (const [slug, info] of Object.entries(legacy?.skills ?? {})) {
    if (!next.skills[slug]) {
      next.skills[slug] = info;
      added++;
    }
  }
  if (added > 0) {
    try {
      fs.mkdirSync(newLockDir, { recursive: true });
      fs.writeFileSync(newLockPath, JSON.stringify(next, null, 2) + "\n", "utf-8");
      debugLog(`migrate clawhub lock: ${added} entries merged`);
    } catch (err: any) {
      debugLog(`migrate clawhub lock failed: ${err?.message ?? err}`);
    }
  }
}

// 执行 clawhub CLI 命令，返回 stdout
function execClawhub(args: string[]): Promise<{ stdout: string; stderr: string }> {
  const nodeBin = resolveNodeBin();
  const clawhubEntry = resolveClawhubEntry();
  const registry = registryUrl();
  const workdir = skillsWorkdir();

  // 构建完整参数：node clawhub-entry --workdir <workdir> --registry <registry> --no-input <args>
  const fullArgs = [clawhubEntry, "--workdir", workdir, "--registry", registry, "--no-input", ...args];
  debugLog(`exec: ${nodeBin} ${fullArgs.join(" ")}`);

  return new Promise((resolve, reject) => {
    // 组装 PATH，确保内嵌 node 和 clawhub wrapper 可找到
    const userBinDir = resolveUserBinDir();
    const envPath = userBinDir + path.delimiter + (process.env.PATH ?? "");

    execFile(nodeBin, fullArgs, {
      timeout: 60_000,
      env: {
        ...process.env,
        ...resolveNodeExtraEnv(),
        PATH: envPath,
      },
      windowsHide: true,
    }, (err, stdout, stderr) => {
      const out = typeof stdout === "string" ? stdout : "";
      const errOut = typeof stderr === "string" ? stderr : "";
      debugLog(`exec result: exit=${err ? (err as any).code ?? "error" : 0} stdout=${out.length}B stderr=${errOut.length}B`);
      if (errOut.trim()) debugLog(`exec stderr: ${errOut.trim()}`);
      if (err) {
        reject(new Error(errOut.trim() || err.message));
        return;
      }
      resolve({ stdout: out, stderr: errOut });
    });
  });
}

// 通用二进制 GET 请求（下载 zip），带超时控制
function binaryGet(url: string): Promise<Buffer> {
  debugLog(`DOWNLOAD ${url}`);
  const startMs = Date.now();
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const mod = parsed.protocol === "https:" ? https : http;
    const req = mod.get(url, { timeout: 120_000 }, (res) => {
      if (res.statusCode && (res.statusCode < 200 || res.statusCode >= 300)) {
        debugLog(`DOWNLOAD ${url} → ${res.statusCode} (${Date.now() - startMs}ms)`);
        res.resume();
        reject(new Error(`HTTP ${res.statusCode}`));
        return;
      }
      const chunks: Buffer[] = [];
      res.on("data", (chunk: Buffer) => chunks.push(chunk));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        debugLog(`DOWNLOAD ${url} → ${res.statusCode} ${buf.length}B (${Date.now() - startMs}ms)`);
        resolve(buf);
      });
    });
    req.on("error", (err) => {
      debugLog(`DOWNLOAD ${url} → error: ${err.message} (${Date.now() - startMs}ms)`);
      reject(err);
    });
    req.on("timeout", () => {
      debugLog(`DOWNLOAD ${url} → timeout (${Date.now() - startMs}ms)`);
      req.destroy();
      reject(new Error("download timeout"));
    });
  });
}

// 手动安装歧义 slug 的技能（绕过 clawhub CLI，直接从 registry API 下载）
// 当多个作者使用同一 slug 时，clawhub CLI 无法消歧，此处通过 ownerHandle 参数直接下载
async function manualInstallSkill(slug: string, ownerHandle: string): Promise<string> {
  const base = registryUrl();
  // 1. 获取技能元数据（含 ownerHandle 消歧）
  const metaUrl = `${base}/api/v1/skills/${encodeURIComponent(slug)}?ownerHandle=${encodeURIComponent(ownerHandle)}`;
  const meta = await jsonGet<any>(metaUrl);
  const skill = meta.skill ?? meta;
  const version = skill.latestVersion?.version ?? skill.tags?.latest ?? skill.version ?? null;
  if (!version) throw new Error("Could not determine skill version");

  // 2. 下载 zip
  const dlParams = new URLSearchParams({ slug, version, ownerHandle });
  const zipBuffer = await binaryGet(`${base}/api/v1/download?${dlParams}`);

  // 3. 保存到临时文件并解压
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "packclaw-skill-"));
  const tmpZip = path.join(tmpDir, `${slug}.zip`);
  fs.writeFileSync(tmpZip, zipBuffer);

  // 确定目标目录（已存在则追加 -N）
  const skillsDir = skillsBaseDir();
  fs.mkdirSync(skillsDir, { recursive: true });
  let targetDir = path.join(skillsDir, slug);
  let dirName = slug;
  if (fs.existsSync(targetDir)) {
    let n = 2;
    while (fs.existsSync(path.join(skillsDir, `${slug}-${n}`))) n++;
    dirName = `${slug}-${n}`;
    targetDir = path.join(skillsDir, dirName);
  }

  try {
    await extractZip(tmpZip, { dir: targetDir });
  } finally {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }

  // 4. 更新 lock.json
  const lockDir = path.join(skillsWorkdir(), ".clawhub");
  const lockPath = path.join(lockDir, "lock.json");
  let lock: any = { version: 1, skills: {} };
  try { lock = JSON.parse(fs.readFileSync(lockPath, "utf-8")); } catch { /* new */ }
  lock.skills ??= {};
  lock.skills[dirName] = { version, installedAt: Date.now() };
  fs.mkdirSync(lockDir, { recursive: true });
  fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + "\n", "utf-8");

  // 5. 记录 ownerHandle 到 _meta.json（供 list-installed 构建 ref 消歧）
  try {
    const metaPath = path.join(targetDir, "_meta.json");
    let meta: any = {};
    try { meta = JSON.parse(fs.readFileSync(metaPath, "utf-8")); } catch { /* new */ }
    meta.ownerHandle = ownerHandle;
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2) + "\n", "utf-8");
  } catch { /* non-critical */ }

  debugLog(`manual install: ${dirName} v${version} (owner=${ownerHandle})`);
  return dirName;
}

// 通过 clawhub CLI 安装技能（歧义 slug 自动回退到手动安装）
async function installSkill(slug: string, displayName?: string, ownerHandle?: string, version?: string, downloads?: number): Promise<{ success: boolean; message?: string }> {
  const saveDisplayName = (dirSlug: string) => {
    if (displayName && displayName.trim()) {
      const map = readDisplayNames();
      putDisplayName(map, dirSlug, displayName.trim());
      writeDisplayNames(map);
    }
  };
  const saveStoreMeta = (dirSlug: string) => {
    if (version || downloads) {
      const map = readStoreMeta();
      putStoreMeta(map, dirSlug, version, downloads);
      writeStoreMeta(map);
    }
  };
  // 把 ownerHandle 写入 _meta.json，供 list-installed 构建 ref（商店卡片按 ref 匹配已安装状态）
  const saveOwnerHandle = (dirSlug: string) => {
    if (!ownerHandle) return;
    try {
      const metaPath = path.join(skillsBaseDir(), dirSlug, "_meta.json");
      let meta: any = {};
      try { meta = JSON.parse(fs.readFileSync(metaPath, "utf-8")); } catch { /* new */ }
      if (meta.ownerHandle !== ownerHandle) {
        meta.ownerHandle = ownerHandle;
        fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2) + "\n", "utf-8");
      }
    } catch { /* non-critical */ }
  };
  try {
    // 始终用 --force：网关启用的技能卸载后可能残留目录，避免 "Already installed" 错误
    await execClawhub(["install", "--force", slug]);
    saveDisplayName(slug);
    saveStoreMeta(slug);
    saveOwnerHandle(slug);
    ensureFrontmatter(slug);
    pipInstallRequirements(slug);
    return { success: true };
  } catch (err: any) {
    const msg = err?.message ?? String(err);
    // 歧义 slug：clawhub CLI 不支持消歧，改用 API 直接下载
    if (ownerHandle && msg.includes("AMBIGUOUS_SKILL_SLUG")) {
      debugLog(`ambiguous slug "${slug}", falling back to manual install (owner=${ownerHandle})`);
      try {
        const dirName = await manualInstallSkill(slug, ownerHandle);
        saveDisplayName(dirName);
        saveStoreMeta(dirName);
        ensureFrontmatter(dirName);
        pipInstallRequirements(dirName);
        return { success: true };
      } catch (err2: any) {
        return { success: false, message: err2?.message ?? String(err2) };
      }
    }
    return { success: false, message: msg };
  }
}

// 根据名称或 slug 解析实际安装目录名
function resolveInstalledSlug(nameOrSlug: string): string {
  const installed = listInstalledSkills();
  // 直接匹配目录名
  if (installed.includes(nameOrSlug)) return nameOrSlug;
  // 从 SKILL.md 读取 name 字段反查（支持 frontmatter `name:` 和 Markdown `# title`）
  const base = skillsBaseDir();
  const needle = nameOrSlug.toLowerCase();
  for (const dir of installed) {
    try {
      const md = fs.readFileSync(path.join(base, dir, "SKILL.md"), "utf-8");
      // frontmatter: name: xxx
      const fm = md.match(/^name:\s*["']?(.+?)["']?\s*$/m);
      if (fm && fm[1].trim().toLowerCase() === needle) return dir;
      // Markdown heading: # xxx
      const h1 = md.match(/^#\s+(.+)/m);
      if (h1 && h1[1].trim().toLowerCase() === needle) return dir;
    } catch { /* skip */ }
  }
  return nameOrSlug;
}

// 通过 clawhub CLI 卸载技能
async function uninstallSkill(slug: string): Promise<{ success: boolean; message?: string }> {
  try {
    const resolved = resolveInstalledSlug(slug);
    debugLog(`uninstall: "${slug}" → resolved="${resolved}"`);
    // 目录已不存在视为成功（可能已被其他途径删除）
    const skillDir = path.join(skillsBaseDir(), resolved);
    if (!fs.existsSync(skillDir)) {
      debugLog(`uninstall: dir not found "${skillDir}", treating as success`);
      return { success: true };
    }
    // 卸载前读取 frontmatter name（卸载后 SKILL.md 被删除）
    const fmName = readFrontmatterName(resolved);
    await execClawhub(["uninstall", "--yes", resolved]);
    // 清除展示名映射（slug + frontmatter name 两个 key）
    const map = readDisplayNames();
    let changed = false;
    for (const key of [resolved, slug]) {
      if (map[key]) { delete map[key]; changed = true; }
    }
    if (fmName && map[fmName]) { delete map[fmName]; changed = true; }
    if (changed) writeDisplayNames(map);
    // 清除 store meta 映射
    const metaMap = readStoreMeta();
    let metaChanged = false;
    for (const key of [resolved, slug, fmName].filter(Boolean) as string[]) {
      if (metaMap[key]) { delete metaMap[key]; metaChanged = true; }
    }
    if (metaChanged) writeStoreMeta(metaMap);
    return { success: true };
  } catch (err: any) {
    const msg = err?.message ?? String(err);
    // "Not installed" 说明技能已经不在了，视为成功
    if (msg.includes("Not installed")) {
      debugLog(`uninstall: already removed, treating as success`);
      return { success: true };
    }
    return { success: false, message: msg };
  }
}

// 列出本地已安装的技能 slug（直接读目录，不依赖 CLI）
function listInstalledSkills(): string[] {
  const base = skillsBaseDir();
  if (!fs.existsSync(base)) return [];
  try {
    return fs.readdirSync(base).filter((name) => {
      const dir = path.join(base, name);
      return fs.statSync(dir).isDirectory() && fs.existsSync(path.join(dir, "SKILL.md"));
    });
  } catch {
    return [];
  }
}

// ── IPC 注册 ──

// 从 lock.json 回填 skill-store-meta.json（版本号），确保已安装技能在启动时就显示版本
function seedStoreMetaFromLock(): void {
  const lockPath = path.join(skillsWorkdir(), ".clawhub", "lock.json");
  let lock: { skills?: Record<string, { version?: string }> } | null = null;
  try {
    lock = JSON.parse(fs.readFileSync(lockPath, "utf-8"));
  } catch {
    return;
  }
  const installed = new Set(listInstalledSkills());
  const metaMap = readStoreMeta();
  let changed = false;
  for (const [slug, info] of Object.entries(lock?.skills ?? {})) {
    if (!installed.has(slug)) continue;
    if (metaMap[slug]?.version) continue; // 已有版本号，跳过
    const fmName = readFrontmatterName(slug);
    // 同时检查 slug 和 frontmatter name 是否已有
    if (fmName && metaMap[fmName]?.version) continue;
    putStoreMeta(metaMap, slug, info.version, metaMap[slug]?.downloads);
    changed = true;
  }
  if (changed) {
    writeStoreMeta(metaMap);
    debugLog(`seedStoreMeta: seeded ${Object.keys(metaMap).length} entries from lock.json`);
  }
}

// 注册技能商店相关 IPC handler
export function registerSkillStoreIpc(): void {
  migrateLegacySkills();
  seedStoreMetaFromLock();
  ipcMain.handle("skill-store:list", async (_event, params) => {
    debugLog(`ipc list sort=${params?.sort} limit=${params?.limit} cursor=${params?.cursor ?? "none"}`);
    try {
      const result = await listSkills({
        sort: params?.sort,
        limit: params?.limit,
        cursor: params?.cursor,
      });
      debugLog(`ipc list → ${result.skills?.length ?? 0} skills`);
      return { success: true, data: result };
    } catch (err: any) {
      debugLog(`ipc list → error: ${err?.message}`);
      return { success: false, message: err?.message ?? String(err) };
    }
  });

  ipcMain.handle("skill-store:search", async (_event, params) => {
    debugLog(`ipc search q="${params?.q}" limit=${params?.limit}`);
    try {
      const result = await searchSkills({
        q: params?.q ?? "",
        limit: params?.limit,
      });
      debugLog(`ipc search → ${result.skills?.length ?? 0} skills`);
      return { success: true, data: result };
    } catch (err: any) {
      debugLog(`ipc search → error: ${err?.message}`);
      return { success: false, message: err?.message ?? String(err) };
    }
  });

  ipcMain.handle("skill-store:detail", async (_event, params) => {
    debugLog(`ipc detail slug=${params?.slug}`);
    try {
      const result = await getSkillDetail(params?.slug ?? "");
      debugLog(`ipc detail → ${result.name ?? "unknown"}`);
      return { success: true, data: result };
    } catch (err: any) {
      debugLog(`ipc detail → error: ${err?.message}`);
      return { success: false, message: err?.message ?? String(err) };
    }
  });

  ipcMain.handle("skill-store:install", async (_event, params) => {
    debugLog(`ipc install slug=${params?.slug} owner=${params?.ownerHandle ?? "none"} displayName=${params?.displayName ?? "none"} v=${params?.version ?? "?"}`);
    const result = await installSkill(params?.slug ?? "", params?.displayName, params?.ownerHandle, params?.version, params?.downloads);
    debugLog(`ipc install → ${result.success ? "ok" : result.message}`);
    return result;
  });

  ipcMain.handle("skill-store:uninstall", async (_event, params) => {
    debugLog(`ipc uninstall slug=${params?.slug}`);
    const result = await uninstallSkill(params?.slug ?? "");
    debugLog(`ipc uninstall → ${result.success ? "ok" : result.message}`);
    return result;
  });

  ipcMain.handle("skill-store:list-installed", async () => {
    const dirs = listInstalledSkills();
    // 构建 ref 列表：有 ownerHandle 的技能返回 @owner/slug，否则返回目录名
    const refs = dirs.map((dir) => {
      try {
        const meta = JSON.parse(fs.readFileSync(path.join(skillsBaseDir(), dir, "_meta.json"), "utf-8"));
        if (meta.ownerHandle) return `@${meta.ownerHandle}/${dir}`;
      } catch { /* no meta */ }
      return dir;
    });
    debugLog(`ipc list-installed → [${refs.join(", ")}]`);
    return { success: true, data: refs };
  });

  ipcMain.handle("skill-store:get-display-names", async () => {
    return { success: true, data: readDisplayNames(), meta: readStoreMeta() };
  });
}
