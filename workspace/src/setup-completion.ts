import { readPackclawConfig } from "./packclaw-config";

// 旧逻辑保留：检查 openclaw.json 的 wizard.lastRunAt（gateway schema 兼容）
export function isSetupCompleteFromConfig(config: any): boolean {
  if (!config || typeof config !== "object") {
    return false;
  }

  const wizard = config.wizard;
  // 仅当最后一步成功写入 lastRunAt 时，才视为真正完成 Setup。
  return !!(
    wizard &&
    typeof wizard === "object" &&
    typeof wizard.lastRunAt === "string" &&
    wizard.lastRunAt.trim() !== ""
  );
}

// 基于 packclaw.config.json 判定 Setup 是否完成
export function isPackclawSetupComplete(): boolean {
  const config = readPackclawConfig();
  return !!(config?.setupCompletedAt);
}
