import { html, nothing } from "lit";
import type { AppViewState } from "../../app-view-state.ts";
import { t } from "../../i18n.ts";
import * as ipc from "../../data/ipc-bridge.ts";
import "../../components/password-input.ts";
import "../../components/message-box.ts";
import {
  PROVIDERS, CUSTOM_MODEL_SENTINEL,
} from "./setup-constants.ts";
import { API_51KEY, KEY_51KEY_LOCAL_STATE } from "./provider-51key-config.ts";

export interface Setup51keyState {
  currentProvider: string;
  modelId: string;
  customModelId: string;
  showCustomModelInput: boolean;
  apiKey: string;
  verifying: boolean;
  error: string | null;
  "51keyEmail": string;
  "51keyCode": string;
  "51keySending": boolean;
  "51keyCountdown": number;
  "51keyLoginLoading": boolean;
  "51keyApiKeyRetrieved": boolean;
  "51keyApiKey": string;
  "51keyBalance": string;
  "51keyToken": string;
}

const KEY_51KEY_LOADED = "packclaw.51key.setup.loaded";
let countdownTimer: ReturnType<typeof setInterval> | null = null;

export function init51keyDefaults(): Partial<Setup51keyState> {
  return {
    "51keyEmail": "",
    "51keyCode": "",
    "51keySending": false,
    "51keyCountdown": 0,
    "51keyLoginLoading": false,
    "51keyApiKeyRetrieved": false,
    "51keyApiKey": "",
    "51keyBalance": "",
    "51keyToken": "",
  };
}

export function load51keyState(s: Setup51keyState) {
  try {
    const raw = localStorage.getItem(KEY_51KEY_LOCAL_STATE);
    if (!raw) return;
    const data = JSON.parse(raw);
    if (data.apiKey) {
      s["51keyEmail"] = data.email || "";
      s["51keyApiKey"] = data.apiKey;
      s.apiKey = data.apiKey;
      s["51keyBalance"] = data.balance || "";
      s["51keyToken"] = data.token || "";
      s["51keyApiKeyRetrieved"] = true;
      if (data.modelId) s.modelId = data.modelId;
    }
  } catch {}
}

function save51keyState(s: Setup51keyState) {
  try {
    localStorage.setItem(KEY_51KEY_LOCAL_STATE, JSON.stringify({
      email: s["51keyEmail"],
      apiKey: s["51keyApiKey"],
      balance: s["51keyBalance"],
      modelId: s.modelId,
      token: s["51keyToken"],
    }));
  } catch {}
}

export function ensure51keyStateLoaded(s: Setup51keyState) {
  try {
    if (localStorage.getItem(KEY_51KEY_LOADED)) return;
    localStorage.setItem(KEY_51KEY_LOADED, "1");
  } catch {}
  load51keyState(s);
  const models = PROVIDERS["51key"]?.models ?? [];
  if (!s.modelId && models.length) s.modelId = models[0];
}

export function handle51keyProviderChange(s: Setup51keyState, state: AppViewState) {
  load51keyState(s);
  if (!s.modelId) {
    const models = PROVIDERS["51key"]?.models ?? [];
    if (models.length) s.modelId = models[0];
  }
  state.requestUpdate();
}

export async function handle51keySendCode(s: Setup51keyState, state: AppViewState) {
  const email = s["51keyEmail"].trim();
  if (!email) { s.error = t("settings.provider.51key.noEmail"); state.requestUpdate(); return; }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { s.error = t("settings.provider.51key.invalidEmail"); state.requestUpdate(); return; }
  s.error = null;
  state.requestUpdate();
  try {
    const resp = await fetch(API_51KEY.SEND_VERIFY_CODE, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, channel: API_51KEY.CHANNEL }),
    });
    if (!resp.ok) {
      const data = await resp.json().catch(() => ({}));
      s.error = data.message || data.error || t("setup.error.connection");
      state.requestUpdate();
      return;
    }
    s["51keySending"] = true;
    s["51keyCountdown"] = 60;
    state.requestUpdate();
    countdownTimer = setInterval(() => {
      s["51keyCountdown"]--;
      if (s["51keyCountdown"] <= 0) {
        s["51keyCountdown"] = 0;
        s["51keySending"] = false;
        if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
      }
      state.requestUpdate();
    }, 1000);
  } catch (e: any) {
    s.error = e?.message ?? t("setup.error.connection");
    state.requestUpdate();
  }
}

export async function handle51keyLogin(s: Setup51keyState, state: AppViewState) {
  const email = s["51keyEmail"].trim();
  const code = s["51keyCode"].trim();
  if (!email) { s.error = t("settings.provider.51key.noEmail"); state.requestUpdate(); return; }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { s.error = t("settings.provider.51key.invalidEmail"); state.requestUpdate(); return; }
  if (!code) { s.error = t("settings.provider.51key.noCode"); state.requestUpdate(); return; }
  if (!/^\d{4,6}$/.test(code)) { s.error = t("settings.provider.51key.invalidCode"); state.requestUpdate(); return; }

  s["51keyLoginLoading"] = true;
  s.error = null;
  state.requestUpdate();

  try {
    const loginResp = await fetch(API_51KEY.LOGIN_BY_CODE, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, verify_code: code, invite_code: "", channel: API_51KEY.CHANNEL }),
    });
    const loginData = await loginResp.json();
    if (!loginResp.ok || loginData.code !== 0) {
      s["51keyLoginLoading"] = false;
      s.error = loginData.message || loginData.error || t("setup.error.verifyFailed");
      state.requestUpdate();
      return;
    }

    const token = loginData.data?.access_token || "";
    s["51keyToken"] = token;

    const keyResp = await fetch(API_51KEY.KEY_LIST, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    });
    const keyData = await keyResp.json();
    if (!keyResp.ok || keyData.code !== 0) {
      s["51keyLoginLoading"] = false;
      s.error = keyData.message || keyData.error || t("setup.error.verifyFailed");
      state.requestUpdate();
      return;
    }

    const recordList = keyData.data?.recordList || [];
    if (recordList.length === 0) {
      s["51keyLoginLoading"] = false;
      s.error = t("settings.provider.51key.noApiKey");
      state.requestUpdate();
      return;
    }

    const api_key = recordList[0].openKey || "";
    s["51keyApiKey"] = api_key;
    s.apiKey = api_key;

    let balance = "";
    try {
      const meResp = await fetch(API_51KEY.USER_INFO, {
        method: "GET",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      });
      const meData = await meResp.json();
      if (meResp.ok && meData.code === 0) {
        balance = meData.data?.apiNum ?? "";
      }
    } catch {}

    s["51keyBalance"] = balance;
    s["51keyApiKeyRetrieved"] = true;
    s["51keyLoginLoading"] = false;

    const models = PROVIDERS["51key"]?.models ?? [];
    if (models.length && !s.modelId) s.modelId = models[0];

    save51keyState(s);
    state.requestUpdate();
  } catch (e: any) {
    s["51keyLoginLoading"] = false;
    s.error = e?.message ?? t("setup.error.connection");
    state.requestUpdate();
  }
}

export function handle51keyVerifyAndContinue(
  s: Setup51keyState & { verifying: boolean; error: string | null; customModelId: string; showCustomModelInput: boolean },
  state: AppViewState,
  goToStep: (step: number) => void,
) {
  if (s.verifying) return;
  const apiKey = s.apiKey.trim();
  if (!apiKey) { s.error = t("setup.error.noKey"); state.requestUpdate(); return; }
  const mid = s.showCustomModelInput ? s.customModelId.trim() : s.modelId;
  if (!mid) { s.error = t("setup.error.noModelId"); state.requestUpdate(); return; }

  const params = {
    provider: "51key",
    apiKey,
    modelID: mid,
    subPlatform: "",
    customPreset: "",
    apiType: "",
    baseURL: "",
    supportImage: true,
  };

  s.verifying = true;
  s.error = null;
  state.requestUpdate();

  (async () => {
    try {
      const result = await ipc.verifyKey(params);
      if (!result.success) {
        s.error = result.message ?? t("setup.error.verifyFailed");
        s.verifying = false;
        state.requestUpdate();
        return;
      }
      await ipc.saveConfig({
        provider: params.provider,
        apiKey: params.apiKey,
        modelID: params.modelID,
        baseURL: params.baseURL ?? "",
        api: params.apiType ?? "",
        subPlatform: params.subPlatform ?? "",
        supportImage: params.supportImage ?? true,
        customPreset: params.customPreset ?? "",
      });
      s.verifying = false;
      goToStep(3);
    } catch (e: any) {
      s.error = t("setup.error.connection") + (e?.message ?? "");
      s.verifying = false;
      state.requestUpdate();
    }
  })();
}

export function render51keySection(
  s: Setup51keyState & { customModelId: string; showCustomModelInput: boolean },
  state: AppViewState,
) {
  const key51Models = PROVIDERS["51key"]?.models ?? [];
  const loggedIn = s["51keyApiKeyRetrieved"];

  return html`
    ${!loggedIn ? html`
      <div style="display:flex;flex-direction:column;gap:0">
        <div class="oc-setup-form-group">
          <label class="oc-setup-label">${t("settings.provider.51key.email")}</label>
          <input class="oc-setup-input" type="email" .value=${s["51keyEmail"]}
            placeholder=${t("settings.provider.51key.emailPlaceholder")}
            @input=${(e: Event) => { s["51keyEmail"] = (e.target as HTMLInputElement).value; }} />
        </div>
        <div class="oc-setup-form-group">
          <label class="oc-setup-label">${t("settings.provider.51key.code")}</label>
          <div style="display:flex;gap:8px;align-items:center">
            <input class="oc-setup-input" style="flex:1;min-width:0" .value=${s["51keyCode"]}
              placeholder=${t("settings.provider.51key.codePlaceholder")}
              @input=${(e: Event) => { s["51keyCode"] = (e.target as HTMLInputElement).value; }} />
            <button class="oc-setup-btn oc-setup-btn--secondary" style="white-space:nowrap;flex-shrink:0;padding:8px 16px"
              ?disabled=${s["51keySending"]}
              @click=${() => handle51keySendCode(s, state)}>
              ${s["51keySending"] ? `${s["51keyCountdown"]}s` : t("settings.provider.51key.sendCode")}
            </button>
          </div>
        </div>
        <div style="display:flex;justify-content:flex-end;margin-top:8px">
          <button class="oc-setup-btn oc-setup-btn--primary" ?disabled=${s["51keyLoginLoading"]}
            @click=${() => handle51keyLogin(s, state)}>
            ${s["51keyLoginLoading"] ? t("setup.provider.51key.loggingIn") : t("settings.provider.51key.login")}
          </button>
        </div>
      </div>
    ` : html`
      <div style="display:flex;flex-direction:column;gap:0">
        <div class="oc-setup-form-group">
          <label class="oc-setup-label">${t("settings.provider.51key.email")}</label>
          <input class="oc-setup-input" type="email" readonly .value=${s["51keyEmail"]} />
        </div>
        <div class="oc-setup-form-group">
          <label class="oc-setup-label">${t("setup.provider.51key.balance")}</label>
          <div style="display:flex;align-items:center;gap:8px">
            <input class="oc-setup-input" style="flex:1" readonly .value=${s["51keyBalance"] + " " + t("setup.provider.51key.yuan")} />
            <a style="font-size:13px;color:var(--accent);cursor:pointer;white-space:nowrap"
              @click=${(e: Event) => { e.preventDefault(); ipc.openExternal(API_51KEY.RECHARGE_URL); }}>
              ${t("setup.provider.51key.recharge")}
            </a>
          </div>
        </div>
        <div class="oc-setup-form-group">
          <label class="oc-setup-label">${t("setup.provider.apiKey")}</label>
          <oc-password-input .value=${s.apiKey} readonly></oc-password-input>
        </div>
        ${key51Models.length > 0 ? html`
          <div class="oc-setup-form-group">
            <label class="oc-setup-label">${t("setup.provider.model")}</label>
            <select class="oc-setup-select" .value=${s.modelId}
              @change=${(e: Event) => {
                const v = (e.target as HTMLSelectElement).value;
                if (v === CUSTOM_MODEL_SENTINEL) {
                  s.showCustomModelInput = true;
                  s.modelId = v;
                } else {
                  s.showCustomModelInput = false;
                  s.modelId = v;
                  s.customModelId = "";
                }
                state.requestUpdate();
              }}>
              ${key51Models.map(m => html`<option value=${m} ?selected=${s.modelId === m}>${m}</option>`)}
              <option value=${CUSTOM_MODEL_SENTINEL}>${t("setup.provider.customModelOption")}</option>
            </select>
          </div>
        ` : nothing}
        ${s.showCustomModelInput ? html`
          <div class="oc-setup-form-group">
            <label class="oc-setup-label">${t("setup.provider.customModelId")}</label>
            <input class="oc-setup-input" .value=${s.customModelId}
              @input=${(e: Event) => { s.customModelId = (e.target as HTMLInputElement).value; }} />
          </div>
        ` : nothing}
      </div>
    `}

    ${!loggedIn ? html`<oc-message-box .message=${s.error ?? ""} .type=${"error"} .visible=${!!s.error}></oc-message-box>` : nothing}
  `;
}
