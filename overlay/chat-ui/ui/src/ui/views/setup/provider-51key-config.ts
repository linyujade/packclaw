import type { ProviderDef } from "./setup-constants.ts";

export const PROVIDER_51KEY: ProviderDef = {
  placeholder: "",
  // models: ["gpt-5.1", "gpt-5.1-mini", "gpt-5.1-codex"],
  models: [
    "glm-5.1",
    "minimax-m2",
    "deepseek-v3.2",
    "deepseek-v4-pro",
    "deepseek-v4-flash",
    "kimi-k2.6",
    "gemini-3.5-flash",
    "gemini-3.1-pro-preview",
    "gpt-5.4",
    "gpt-5.5",
    "claude-opus-4-7",
    "claude-sonnet-4-6",
  ],
};

export const KEY_51KEY_LOCAL_STATE = "packclaw.51key.state";

export const API_51KEY = {
  BASE_URL: "https://api.lmdone.com/v1",
  SEND_VERIFY_CODE: "https://api.lmdone.com/v1/sendVerifyCode",
  LOGIN_BY_CODE: "https://api.lmdone.com/v1/loginByCode",
  GET_API_KEY_BY_TOKEN: "https://api.lmdone.com/v1/getAPIKeyByToken",
  KEY_LIST: "https://api.lmdone.com/v1/service/keyList",
  USER_INFO: "https://api.lmdone.com/v1/me",
  RECHARGE_URL: "https://www.51key.com/space/recharge",
  WEBSITE: "https://www.51key.com/",
  CHANNEL: "51key",
} as const;
