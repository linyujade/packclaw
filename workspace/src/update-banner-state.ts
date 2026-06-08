export type UpdateBannerStatus = "hidden" | "available" | "downloading" | "ready-to-install";

export type UpdateBannerState = {
  status: UpdateBannerStatus;
  version: string | null;
  percent: number | null;
  showBadge: boolean;
};

export type UpdateBannerEvent =
  | { type: "update-available"; version: string }
  | { type: "update-not-available" }
  | { type: "download-started" }
  | { type: "download-progress"; percent: number }
  | { type: "download-failed" }
  | { type: "download-finished" }
  | { type: "download-ready" };

export function createInitialUpdateBannerState(): UpdateBannerState {
  return {
    status: "hidden",
    version: null,
    percent: null,
    showBadge: false,
  };
}

function normalizePercent(input: number): number {
  if (!Number.isFinite(input)) {
    return 0;
  }
  if (input < 0) {
    return 0;
  }
  if (input > 100) {
    return 100;
  }
  return input;
}

export function reduceUpdateBannerState(
  state: UpdateBannerState,
  event: UpdateBannerEvent,
): UpdateBannerState {
  switch (event.type) {
    case "update-available":
      return {
        status: "available",
        version: event.version.trim() || state.version,
        percent: null,
        showBadge: true,
      };
    case "update-not-available":
      return createInitialUpdateBannerState();
    case "download-finished":
      return createInitialUpdateBannerState();
    case "download-ready":
      if (!state.version) {
        return createInitialUpdateBannerState();
      }
      return {
        status: "ready-to-install",
        version: state.version,
        percent: null,
        showBadge: true,
      };
    case "download-started":
      if (state.status !== "available" || !state.version) {
        return state;
      }
      return {
        status: "downloading",
        version: state.version,
        percent: 0,
        showBadge: false,
      };
    case "download-progress":
      if (state.status !== "downloading") {
        return state;
      }
      return {
        ...state,
        percent: normalizePercent(event.percent),
      };
    case "download-failed":
      if (!state.version) {
        return createInitialUpdateBannerState();
      }
      return {
        status: "available",
        version: state.version,
        percent: null,
        showBadge: true,
      };
    default:
      return state;
  }
}

// 仅在“已发现更新”时允许启动下载，避免重复触发下载任务。
export function canStartUpdateDownload(state: UpdateBannerState): boolean {
  return state.status === "available" && Boolean(state.version);
}
