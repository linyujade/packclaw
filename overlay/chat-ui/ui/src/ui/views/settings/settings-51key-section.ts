import { html, nothing } from "lit";
import type { AppViewState } from "../../app-view-state.ts";
import { t } from "../../i18n.ts";
import * as ipc from "../../data/ipc-bridge.ts";
import "../../components/password-input.ts";
import "../../components/message-box.ts";
import {
  PROVIDERS, CUSTOM_MODEL_SENTINEL,
} from "../setup/setup-constants.ts";
import { API_51KEY } from "../setup/provider-51key-config.ts";
import {
  handle51keySendCode, handle51keyLogin,
} from "../setup/setup-51key-section.ts";
import type { Setup51keyState } from "../setup/setup-51key-section.ts";

export interface Settings51keyState extends Setup51keyState {
  saving: boolean;
  successMsg: string | null;
}

export function render51keySettingsSection(
  s: Settings51keyState & { customModelId: string; showCustomModelInput: boolean },
  state: AppViewState,
  handleSave: () => void,
  getSaveButtonLabel: () => string,
  onModelSelectChange: (value: string, state: AppViewState) => void,
) {
  const loggedIn = s["51keyApiKeyRetrieved"];
  const key51Models = PROVIDERS["51key"]?.models ?? [];

  if (loggedIn) {
    return html`
      <div class="oc-settings__form-group" style="margin-top:12px">
        <label class="oc-settings__label">${t("settings.provider.51key.email")}</label>
        <input class="oc-settings__input" type="email" readonly .value=${s["51keyEmail"]} />
      </div>
      <div class="oc-settings__form-group">
        <label class="oc-settings__label">${t("setup.provider.51key.balance")}</label>
        <div style="display:flex;align-items:center;gap:8px">
          <input class="oc-settings__input" style="flex:1" readonly .value=${s["51keyBalance"] + " " + t("setup.provider.51key.yuan")} />
          <a style="font-size:13px;color:var(--accent);cursor:pointer;white-space:nowrap"
            @click=${(e: Event) => { e.preventDefault(); ipc.openExternal(API_51KEY.RECHARGE_URL); }}>
            ${t("setup.provider.51key.recharge")}
          </a>
        </div>
      </div>
      <div class="oc-settings__form-group">
        <label class="oc-settings__label">${t("setup.provider.apiKey")}</label>
        <oc-password-input .value=${s.apiKey} readonly></oc-password-input>
      </div>
      ${key51Models.length > 0 ? html`
        <div class="oc-settings__form-group">
          <label class="oc-settings__label">${t("setup.provider.model")}</label>
          <select class="oc-settings__select" .value=${s.modelId}
            @change=${(e: Event) => onModelSelectChange((e.target as HTMLSelectElement).value, state)}>
            ${key51Models.map(m => html`<option value=${m} ?selected=${s.modelId === m}>${m}</option>`)}
            <option value=${CUSTOM_MODEL_SENTINEL}>${t("setup.provider.customModelOption")}</option>
          </select>
        </div>
      ` : nothing}
      ${s.showCustomModelInput ? html`
        <div class="oc-settings__form-group">
          <label class="oc-settings__label">${t("setup.provider.customModelId")}</label>
          <input class="oc-settings__input" .value=${s.customModelId}
            @input=${(e: Event) => { s.customModelId = (e.target as HTMLInputElement).value; }} />
        </div>
      ` : nothing}
      <oc-message-box .message=${s.error ?? ""} .type=${"error"} .visible=${!!s.error}></oc-message-box>
      <oc-message-box .message=${s.successMsg ?? ""} .type=${"success"} .visible=${!!s.successMsg}></oc-message-box>
      <div class="oc-settings__btn-row">
        <button class="oc-settings__btn oc-settings__btn--primary" ?disabled=${s.saving}
          @click=${handleSave}>
          ${getSaveButtonLabel()}
        </button>
      </div>
    `;
  }

  return html`
    <div style="margin-top:20px;display:flex;flex-direction:column;gap:16px">
      <h3 style="font-size:15px;font-weight:600;margin:0;color:var(--text, #3f3f46)">${t("settings.provider.51key.title")}</h3>
      <div class="oc-settings__form-group">
        <label class="oc-settings__label">${t("settings.provider.51key.email")}</label>
        <input class="oc-settings__input" type="email" .value=${s["51keyEmail"]}
          placeholder=${t("settings.provider.51key.emailPlaceholder")}
          @input=${(e: Event) => { s["51keyEmail"] = (e.target as HTMLInputElement).value; }} />
      </div>
      <div class="oc-settings__form-group">
        <label class="oc-settings__label">${t("settings.provider.51key.code")}</label>
        <div style="display:flex;gap:8px;align-items:center">
          <input class="oc-settings__input" style="flex:1;min-width:0" .value=${s["51keyCode"]}
            placeholder=${t("settings.provider.51key.codePlaceholder")}
            @input=${(e: Event) => { s["51keyCode"] = (e.target as HTMLInputElement).value; }} />
          <button class="oc-settings__btn oc-settings__btn--secondary" style="white-space:nowrap;flex-shrink:0;padding:8px 16px"
            ?disabled=${s["51keySending"]}
            @click=${() => handle51keySendCode(s, state)}>
            ${s["51keySending"] ? `${s["51keyCountdown"]}s` : t("settings.provider.51key.sendCode")}
          </button>
        </div>
      </div>
      <oc-message-box .message=${s.error ?? ""} .type=${"error"} .visible=${!!s.error}></oc-message-box>
      <oc-message-box .message=${s.successMsg ?? ""} .type=${"success"} .visible=${!!s.successMsg}></oc-message-box>
      <div class="oc-settings__btn-row">
        <button class="oc-settings__btn oc-settings__btn--primary" ?disabled=${s["51keyLoginLoading"]}
          @click=${() => handle51keyLogin(s, state)}>
          ${s["51keyLoginLoading"] ? t("setup.provider.51key.loggingIn") : t("settings.provider.51key.login")}
        </button>
      </div>
    </div>
  `;
}
