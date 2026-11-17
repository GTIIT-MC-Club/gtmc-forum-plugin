import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { bind } from "discourse/lib/decorators";
import { isUsableStatusResponse } from "../lib/gtmc-server-status-response.js";

// 请求卡住时不能一直占着「正在请求」的标记，否则之后永远不会再刷新。
// jQuery 超时时 readyState 为 0，见 refresh。
const REQUEST_TIMEOUT_MILLIS = 10_000;

// 第一次请求就失败时还不知道服务器要求的周期，先按这个重试；它与后端
// ServerStatus::REFRESH_INTERVAL_SECONDS 相同，成功过一次之后就以接口返回的为准。
const FALLBACK_REFRESH_INTERVAL_SECONDS = 30;

/**
 * 轮询 GET /gtmc/status.json（契约见 PLAN.md 4.1），桌面右栏面板和手机状态条共用一份数据和一个定时器。
 *
 * 轮询约定：有组件在看（watch）且页面可见时，每 refresh_interval_seconds 请求一次；
 * 页面不可见时暂停，重新可见时立刻请求一次；没有组件在看时停止。
 * 接口失败时 servers 为 null，界面据此显示「状态暂不可用」；不保留上一次的数据，避免展示过期的在线人数。
 */
export default class GtmcServerStatusService extends Service {
  // 最近一次成功拿到的服列表，顺序即接口返回的顺序（后端已排好，前端不再排）。
  // 为 null 且 hasLoaded 为真表示最近一次请求失败。
  @tracked servers = null;
  @tracked hasLoaded = false;
  @tracked refreshIntervalSeconds = FALLBACK_REFRESH_INTERVAL_SECONDS;
  // 每次拿到响应加一，刷新圆环据此重新开始转一圈
  @tracked refreshCount = 0;

  watcherCount = 0;
  refreshTimer = null;
  isRequestInFlight = false;

  willDestroy() {
    super.willDestroy(...arguments);
    document.removeEventListener("visibilitychange", this.handleVisibilityChange);
    clearTimeout(this.refreshTimer);
  }

  get isUnavailable() {
    return this.hasLoaded && !this.servers;
  }

  get hasServers() {
    return this.servers?.length > 0;
  }

  get totalPlayersOnline() {
    return this.servers.reduce(
      (total, server) => total + (server.players_online ?? 0),
      0
    );
  }

  /**
   * 开始为一个组件提供数据，返回停止的函数；组件销毁时必须调用，否则定时器一直转。
   */
  watch() {
    this.watcherCount++;
    if (this.watcherCount === 1) {
      document.addEventListener(
        "visibilitychange",
        this.handleVisibilityChange
      );
      if (document.visibilityState === "visible") {
        this.refresh();
      }
    }

    let isWatching = true;
    return () => {
      if (!isWatching) {
        return;
      }
      isWatching = false;
      this.unwatch();
    };
  }

  unwatch() {
    this.watcherCount--;
    if (this.watcherCount === 0) {
      document.removeEventListener(
        "visibilitychange",
        this.handleVisibilityChange
      );
      clearTimeout(this.refreshTimer);
    }
  }

  @bind
  handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.refresh();
    } else {
      clearTimeout(this.refreshTimer);
    }
  }

  // 失败不弹窗也不抛：对访客来说断网、超时、5xx 没有区别，统一显示「状态暂不可用」，
  // 下一轮自动重试。每 30 秒弹一次错误对话框会比服务器离线本身更打扰人。
  async refresh() {
    if (this.isRequestInFlight) {
      return;
    }
    this.isRequestInFlight = true;
    clearTimeout(this.refreshTimer);

    let response;
    try {
      // ajax 默认 ignoreUnsent: true，断网（readyState 0）时 Promise 既不成功也不失败，
      // 会永远停在上一次的状态；必须关掉它才能走到失败分支。
      response = await ajax("/gtmc/status.json", {
        ignoreUnsent: false,
        timeout: REQUEST_TIMEOUT_MILLIS,
      });
    } catch {
      response = null;
    } finally {
      this.isRequestInFlight = false;
    }

    if (this.isDestroying || this.watcherCount === 0) {
      return;
    }

    if (isUsableStatusResponse(response)) {
      this.servers = response.servers;
      this.refreshIntervalSeconds = response.refresh_interval_seconds;
    } else {
      this.servers = null;
    }
    this.hasLoaded = true;
    this.refreshCount++;
    this.scheduleNextRefresh();
  }

  // 链式 setTimeout 而不是 setInterval：慢请求不会叠在一起。
  // 不用 discourseLater：它在测试里把等待缩成 10 毫秒，递归调用会让测试永远等不到空闲。
  scheduleNextRefresh() {
    if (document.visibilityState !== "visible") {
      return;
    }
    this.refreshTimer = setTimeout(
      () => this.refresh(),
      this.refreshIntervalSeconds * 1000
    );
  }
}
