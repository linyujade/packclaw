/**
 * Setup wizard constants — providers, presets, models, and URLs.
 * Migrated from setup/setup.js.
 */
import { t } from "../../i18n.ts";
import { PROVIDER_51KEY, KEY_51KEY_LOCAL_STATE, API_51KEY } from "./provider-51key-config.ts";

export { KEY_51KEY_LOCAL_STATE, API_51KEY };

export interface ProviderDef {
  placeholder: string;
  platformUrl?: string;
  models: string[];
  hasSubPlatform?: boolean;
}

export interface CustomPresetDef {
  providerKey: string;
  placeholder: string;
  models: string[];
}

export const CUSTOM_MODEL_SENTINEL = "__custom__";

export const PROVIDERS: Record<string, ProviderDef> = {
  moonshot: {
    placeholder: "sk-...",
    models: ["kimi-k2.5", "kimi-k2-0905-preview"],
    hasSubPlatform: true,
  },
  anthropic: {
    placeholder: "sk-ant-...",
    platformUrl: "https://console.anthropic.com?utm_source=packclaw",
    models: [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-sonnet-4-5-20250929",
      "claude-opus-4-5-20251101",
      "claude-haiku-4-5-20251001",
    ],
  },
  openai: {
    placeholder: "sk-...",
    platformUrl: "https://platform.openai.com?utm_source=packclaw",
    models: ["gpt-5.4", "gpt-5.2", "gpt-5.2-codex"],
  },
  google: {
    placeholder: "AI...",
    platformUrl: "https://aistudio.google.com?utm_source=packclaw",
    models: ["gemini-3.1-pro-preview", "gemini-3.1-flash-lite-preview", "gemini-3-flash-preview"],
  },
  "51key": PROVIDER_51KEY,
  custom: {
    placeholder: "",
    models: [],
  },
};

export const CUSTOM_PRESETS: Record<string, CustomPresetDef> = {
  minimax: {
    providerKey: "minimax",
    placeholder: "eyJ...",
    models: ["MiniMax-M2.5", "MiniMax-M2.5-highspeed"],
  },
  "minimax-cn": {
    providerKey: "minimax-cn",
    placeholder: "eyJ...",
    models: ["MiniMax-M2.5", "MiniMax-M2.5-highspeed"],
  },
  "zai-global": {
    providerKey: "zai-global",
    placeholder: "...",
    models: ["glm-5", "glm-4.7", "glm-4.7-flash", "glm-4.7-flashx"],
  },
  "zai-cn": {
    providerKey: "zai-cn",
    placeholder: "...",
    models: ["glm-5", "glm-4.7", "glm-4.7-flash", "glm-4.7-flashx"],
  },
  "zai-cn-coding": {
    providerKey: "zai-cn-coding",
    placeholder: "...",
    models: ["glm-5", "glm-4.7", "glm-4.7-flash", "glm-4.7-flashx"],
  },
  volcengine: {
    providerKey: "volcengine",
    placeholder: "...",
    models: ["doubao-seed-2.0-pro", "doubao-seed-2.0-lite", "doubao-seed-2.0-code", "doubao-seed-code"],
  },
  "volcengine-coding": {
    providerKey: "volcengine-coding",
    placeholder: "...",
    models: [
      "doubao-seed-2.0-code", "doubao-seed-2.0-pro", "doubao-seed-2.0-lite", "doubao-seed-code",
      "minimax-m2.5", "glm-4.7", "deepseek-v3.2", "kimi-k2.5", "ark-code-latest",
    ],
  },
  qwen: {
    providerKey: "qwen",
    placeholder: "sk-...",
    models: ["qwen-coder-plus-latest", "qwen-plus-latest", "qwen-max-latest", "qwen-turbo-latest"],
  },
  "qwen-coding": {
    providerKey: "qwen-coding",
    placeholder: "sk-sp-...",
    models: ["qwen3.5-plus", "kimi-k2.5", "glm-5", "MiniMax-M2.5"],
  },
  deepseek: {
    providerKey: "deepseek",
    placeholder: "sk-...",
    models: ["deepseek-chat", "deepseek-reasoner"],
  },
};

export const KIMI_CODE_MODELS = ["k2p5"];

export const SUB_PLATFORM_URLS: Record<string, string> = {
  "moonshot-cn": "https://platform.moonshot.cn?utm_source=packclaw",
  "moonshot-ai": "https://platform.moonshot.ai?utm_source=packclaw",
  "kimi-code": "https://kimi.com/code?utm_source=packclaw",
};

export const PROVIDER_DISPLAY_ORDER = ["51key", "moonshot", "anthropic", "openai", "google", "custom"] as const;

/** Returns i18n-driven display labels for the provider segment selector. */
export function getProviderLabels(): Record<string, string> {
  return {
    moonshot: t("setup.provider.label.moonshot"),
    anthropic: t("setup.provider.label.anthropic"),
    openai: t("setup.provider.label.openai"),
    google: t("setup.provider.label.google"),
    "51key": t("setup.provider.label.51key"),
    custom: t("setup.provider.label.custom"),
  };
}
