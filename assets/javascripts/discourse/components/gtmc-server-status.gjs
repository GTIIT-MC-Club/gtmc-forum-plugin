import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { bind } from "discourse/lib/decorators";
import DCopyButton from "discourse/ui-kit/d-copy-button";
import { i18n } from "discourse-i18n";

// 与 MC 插件的心跳间隔（30 秒）一致：刷新得比它更勤也看不到新数据。
const REFRESH_INTERVAL_MILLIS = 30_000;

// 请求卡住时不能一直占着「正在请求」的标记，否则之后永远不会再刷新。
// 取刷新间隔的三分之一，留出重试余量；jQuery 超时时 readyState 为 0，见 refreshStatus。
const REQUEST_TIMEOUT_MILLIS = 10_000;

const HTTP_URL_PATTERN = /^https?:\/\//i;

// 响应来自网络，进入组件状态前先确认字段类型；不合格当作接口不可用。
function isUsableStatus(response) {
  if (typeof response?.online !== "boolean") {
    return false;
  }
  if (!response.online) {
    return true;
  }
  return (
    Number.isInteger(response.players_online) &&
    Number.isInteger(response.players_max)
  );
}

/**
 * 首页的 MC 服务器状态条，数据来自 GET /gtmc/status.json（契约见 PLAN.md 4.1）。
 *
 * 轮询约定：页面可见时每 REFRESH_INTERVAL_MILLIS 请求一次；页面不可见时暂停，
 * 重新可见时立刻请求一次；组件销毁时清掉定时器和事件监听。
 */
export default class GtmcServerStatus extends Component {
  // 只在没有按分类或标签筛选的列表上显示，即首页；分类页上重复出现只是干扰。
  // 放在 shouldRender 里而不是模板里，这样不该显示时连组件和定时器都不会创建。
  static shouldRender(outletArgs, helper) {
    return (
      helper.siteSettings.gtmc_enabled &&
      !outletArgs.category &&
      !outletArgs.tag
    );
  }

  @service siteSettings;

  // 最近一次成功拿到的响应；为 null 且 hasLoaded 为真表示最近一次请求失败。
  @tracked status = null;
  @tracked hasLoaded = false;

  refreshTimer = null;
  isRequestInFlight = false;

  constructor() {
    super(...arguments);
    document.addEventListener("visibilitychange", this.handleVisibilityChange);
    if (document.visibilityState === "visible") {
      this.refreshStatus();
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    document.removeEventListener(
      "visibilitychange",
      this.handleVisibilityChange
    );
    clearTimeout(this.refreshTimer);
  }

  get viewState() {
    if (!this.hasLoaded) {
      return "loading";
    }
    if (!this.status) {
      return "unavailable";
    }
    return this.status.online ? "online" : "offline";
  }

  get isOnline() {
    return this.viewState === "online";
  }

  get isOffline() {
    return this.viewState === "offline";
  }

  get isUnavailable() {
    return this.viewState === "unavailable";
  }

  get playersLabel() {
    return i18n("gtmc.server_status.players", {
      online: this.status.players_online,
      max: this.status.players_max,
    });
  }

  get versionLabel() {
    if (!this.status.version) {
      return null;
    }
    return i18n("gtmc.server_status.version", { version: this.status.version });
  }

  get serverAddress() {
    return this.siteSettings.gtmc_server_address;
  }

  get copyAddressAriaLabel() {
    return i18n("gtmc.server_status.copy_address_aria_label", {
      address: this.serverAddress,
    });
  }

  // 站点设置没有格式校验，只放行 http(s)，免得填错成 javascript: 之类的地址被渲染成链接。
  get mapUrl() {
    const mapUrl = this.siteSettings.gtmc_map_url;
    return HTTP_URL_PATTERN.test(mapUrl) ? mapUrl : null;
  }

  @bind
  handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.refreshStatus();
    } else {
      clearTimeout(this.refreshTimer);
    }
  }

  // 失败不弹窗也不抛：对访客来说断网、超时、5xx 没有区别，统一显示「状态暂不可用」，
  // 下一轮自动重试。每 30 秒弹一次错误对话框会比服务器离线本身更打扰人。
  async refreshStatus() {
    if (this.isRequestInFlight) {
      return;
    }
    this.isRequestInFlight = true;
    clearTimeout(this.refreshTimer);

    let response;
    try {
      // ajax 默认 ignoreUnsent: true，断网（readyState 0）时 Promise 既不成功也不失败，
      // 组件会永远停在上一次的状态；必须关掉它才能走到失败分支。
      response = await ajax("/gtmc/status.json", {
        ignoreUnsent: false,
        timeout: REQUEST_TIMEOUT_MILLIS,
      });
    } catch {
      response = null;
    } finally {
      this.isRequestInFlight = false;
    }

    if (this.isDestroying) {
      return;
    }

    this.status = isUsableStatus(response) ? response : null;
    this.hasLoaded = true;
    this.scheduleNextRefresh();
  }

  // 链式 setTimeout 而不是 setInterval：慢请求不会叠在一起。
  // 不用 discourseLater：它在测试里把等待缩成 10 毫秒，递归调用会让测试永远等不到空闲。
  scheduleNextRefresh() {
    if (document.visibilityState !== "visible") {
      return;
    }
    this.refreshTimer = setTimeout(
      () => this.refreshStatus(),
      REFRESH_INTERVAL_MILLIS
    );
  }

  <template>
    <section
      aria-label={{i18n "gtmc.server_status.title"}}
      class="gtmc-server-status gtmc-server-status--{{this.viewState}}"
    >
      {{#if this.isOnline}}
        <div class="gtmc-server-status__summary">
          <span class="gtmc-server-status__headline">{{i18n
              "gtmc.server_status.online"
            }}</span>
          <span class="gtmc-server-status__players">{{this.playersLabel}}</span>
          {{#if this.versionLabel}}
            <span
              class="gtmc-server-status__version"
            >{{this.versionLabel}}</span>
          {{/if}}
        </div>
        <div class="gtmc-server-status__links">
          {{#if this.serverAddress}}
            <DCopyButton
              @ariaLabel={{this.copyAddressAriaLabel}}
              @copyClass="btn-default gtmc-server-status__address"
              @translatedLabel={{this.serverAddress}}
              @translatedLabelAfterCopy={{i18n "gtmc.server_status.copied"}}
              @value={{this.serverAddress}}
            />
          {{/if}}
          {{#if this.mapUrl}}
            <a
              class="gtmc-server-status__map"
              href={{this.mapUrl}}
              rel="noopener noreferrer"
              target="_blank"
            >{{i18n "gtmc.server_status.map"}}</a>
          {{/if}}
        </div>
      {{else if this.isOffline}}
        <div class="gtmc-server-status__summary">
          <span class="gtmc-server-status__headline">{{i18n
              "gtmc.server_status.offline"
            }}</span>
          <span class="gtmc-server-status__hint">{{i18n
              "gtmc.server_status.offline_hint"
            }}</span>
        </div>
      {{else if this.isUnavailable}}
        <div class="gtmc-server-status__summary">
          <span class="gtmc-server-status__headline">{{i18n
              "gtmc.server_status.unavailable"
            }}</span>
          <span class="gtmc-server-status__hint">{{i18n
              "gtmc.server_status.unavailable_hint"
            }}</span>
        </div>
      {{else}}
        <div class="gtmc-server-status__summary">
          <span class="gtmc-server-status__hint">{{i18n
              "gtmc.server_status.loading"
            }}</span>
        </div>
      {{/if}}
    </section>
  </template>
}
