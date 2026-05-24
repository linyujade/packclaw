import { html } from "lit";
import { ref } from "lit/directives/ref.js";
import { icons } from "../icons.ts";
import { API_51KEY } from "../views/setup/provider-51key-config.ts";

let _lastBalanceCheck = 0;
let _cachedBalance: { balance: string; low: boolean } | null = null;

async function check51keyBalance(): Promise<{ balance: string; low: boolean } | null> {
  const now = Date.now();
  if (_cachedBalance && now - _lastBalanceCheck < 30_000) return _cachedBalance;
  try {
    const raw = localStorage.getItem("packclaw.51key.state");
    if (!raw) return null;
    const data = JSON.parse(raw);
    const token = data.token;
    if (!token) return null;
    const resp = await fetch(API_51KEY.USER_INFO, {
      method: "GET",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    });
    const result = await resp.json();
    if (resp.ok && result.code === 0) {
      const balance = String(result.data?.apiNum ?? "0");
      const low = parseFloat(balance) <= 0;
      _cachedBalance = { balance, low };
      _lastBalanceCheck = now;
      data.balance = balance;
      localStorage.setItem("packclaw.51key.state", JSON.stringify(data));
      return _cachedBalance;
    }
  } catch {}
  return null;
}

function is51keyEmptyResponse(m: Record<string, unknown>): boolean {
  if (m.provider !== "51key" || m.role !== "assistant") return false;
  const usage = m.usage as Record<string, unknown> | undefined;
  if (usage && usage.totalTokens === 0) return true;
  const content = m.content;
  if (Array.isArray(content) && content.length === 0) return true;
  return false;
}

export function render51keyEmptyResponse(
  m: Record<string, unknown>,
  bubbleClasses: string,
): ReturnType<typeof html> | null {
  if (!is51keyEmptyResponse(m)) return null;
  return html`
    <div class="${bubbleClasses}" style="min-height:0">
      <div ${ref((el: Element) => {
        if (!(el instanceof HTMLElement)) return;
        check51keyBalance().then((result) => {
          if (result && result.low) {
            el.innerHTML = `<span style="font-size:13px;color:var(--accent, #c0392b)">51key 余额不足（当前余额：${result.balance} 元），请 <a href="#" style="color:var(--accent);text-decoration:underline;cursor:pointer">前往充值</a></span>`;
          } else {
            el.innerHTML = `<span style="font-size:13px;color:var(--text-secondary)">51key 未返回内容，请 <a href="#" style="color:var(--accent);text-decoration:underline;cursor:pointer">前往充值</a> 或在设置中重新登录</span>`;
          }
          const link = el.querySelector("a");
          if (link) {
            link.addEventListener("click", (e) => {
              e.preventDefault();
              import("../data/ipc-bridge.ts").then(({ openExternal }) => openExternal(API_51KEY.RECHARGE_URL));
            });
          }
        });
      })}>${icons.loader}<span style="margin-left:6px;font-size:13px;color:var(--text-secondary)">检查余额中…</span></div>
    </div>
  `;
}
