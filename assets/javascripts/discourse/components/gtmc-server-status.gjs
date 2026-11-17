import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
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

function isUsableServer(server) {
  if (
    typeof server?.server_id !== "string" ||
    typeof server.name !== "string" ||
    typeof server.online !== "boolean"
  ) {
    return false;
  }
  if (!server.online) {
    return true;
  }
  return (
    Number.isInteger(server.players_online) &&
    Number.isInteger(server.players_max)
  );
}

// 响应来自网络，进入组件状态前先确认字段类型。任何一项不合格都当作整个接口不可用：
// 悄悄丢掉某个服会让玩家以为它不存在，比显示「状态暂不可用」更误导人。
function isUsableResponse(response) {
  return (
    Array.isArray(response?.servers) && response.servers.every(isUsableServer)
  );
}

// 站点设置没有格式校验，只放行 http(s)，免得填错成 javascript: 之类的地址被渲染成链接。
function safeMapUrl(mapUrl) {
  return HTTP_URL_PATTERN.test(mapUrl) ? mapUrl : null;
}

// 把接口里的一项变成模板直接用的展示数据，模板里不再做判断和拼接。
function toServerCard(server) {
  const card = {
    serverId: server.server_id,
    name: server.name,
    isOnline: server.online,
    stateClass: server.online
      ? "gtmc-server-card--online"
      : "gtmc-server-card--offline",
    address: server.address || null,
    mapUrl: safeMapUrl(server.map_url),
    copyAddressAriaLabel: i18n("gtmc.server_status.copy_address_aria_label", {
      name: server.name,
      address: server.address,
    }),
    playersLabel: null,
    versionLabel: null,
  };
  if (server.online) {
    card.playersLabel = i18n("gtmc.server_status.players", {
      online: server.players_online,
      max: server.players_max,
    });
    if (server.version) {
      card.versionLabel = i18n("gtmc.server_status.version", {
        version: server.version,
      });
    }
  }
  return card;
}

/**
 * 首页的 MC 服务器状态，每个服一张卡片，数据来自 GET /gtmc/status.json（契约见 PLAN.md 4.1）。
 *
 * 轮询约定：页面可见时每 REFRESH_INTERVAL_MILLIS 请求一次；页面不可见时暂停，
 * 重新可见时立刻请求一次；组件销毁时清掉定时器和事件监听。
 * 接口失败时整体显示「状态暂不可用」，此时没有任何服的数据可显示；没有登记任何服时什么都不渲染。
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

  // 最近一次成功拿到的服列表；为 null 且 hasLoaded 为真表示最近一次请求失败。
  @tracked servers = null;
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

  get isLoading() {
    return !this.hasLoaded;
  }

  get isUnavailable() {
    return this.hasLoaded && !this.servers;
  }

  // 还没有登记任何服时首页上不留一个空框；管理员登记后下一轮刷新就会出现。
  get hasServers() {
    return this.servers?.length > 0;
  }

  get serverCards() {
    return this.servers.map(toServerCard);
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

    // 失败后不保留上一次的数据，免得展示过期的在线人数。
    this.servers = isUsableResponse(response) ? response.servers : null;
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
    {{#if this.isLoading}}
      <section
        aria-label={{i18n "gtmc.server_status.title"}}
        class="gtmc-server-status gtmc-server-status--loading"
      >
        <div class="gtmc-server-status__notice">
          <span class="gtmc-server-status__hint">{{i18n
              "gtmc.server_status.loading"
            }}</span>
        </div>
      </section>
    {{else if this.isUnavailable}}
      <section
        aria-label={{i18n "gtmc.server_status.title"}}
        class="gtmc-server-status gtmc-server-status--unavailable"
      >
        <div class="gtmc-server-status__notice">
          <span class="gtmc-server-status__headline">{{i18n
              "gtmc.server_status.unavailable"
            }}</span>
          <span class="gtmc-server-status__hint">{{i18n
              "gtmc.server_status.unavailable_hint"
            }}</span>
        </div>
      </section>
    {{else if this.hasServers}}
      <section
        aria-label={{i18n "gtmc.server_status.title"}}
        class="gtmc-server-status gtmc-server-status--loaded"
      >
        {{#each this.serverCards key="serverId" as |card|}}
          <article
            aria-label={{card.name}}
            class="gtmc-server-card {{card.stateClass}}"
            data-server-id={{card.serverId}}
          >
            <div class="gtmc-server-card__summary">
              <span class="gtmc-server-card__name">{{card.name}}</span>
              {{#if card.isOnline}}
                <span class="gtmc-server-card__state">{{i18n
                    "gtmc.server_status.online"
                  }}</span>
                <span
                  class="gtmc-server-card__players"
                >{{card.playersLabel}}</span>
                {{#if card.versionLabel}}
                  <span
                    class="gtmc-server-card__version"
                  >{{card.versionLabel}}</span>
                {{/if}}
              {{else}}
                <span class="gtmc-server-card__state">{{i18n
                    "gtmc.server_status.offline"
                  }}</span>
                <span class="gtmc-server-card__hint">{{i18n
                    "gtmc.server_status.offline_hint"
                  }}</span>
              {{/if}}
            </div>
            {{#if card.isOnline}}
              <div class="gtmc-server-card__links">
                {{#if card.address}}
                  <DCopyButton
                    @ariaLabel={{card.copyAddressAriaLabel}}
                    @copyClass="btn-default gtmc-server-card__address"
                    @translatedLabel={{card.address}}
                    @translatedLabelAfterCopy={{i18n
                      "gtmc.server_status.copied"
                    }}
                    @value={{card.address}}
                  />
                {{/if}}
                {{#if card.mapUrl}}
                  <a
                    class="gtmc-server-card__map"
                    href={{card.mapUrl}}
                    rel="noopener noreferrer"
                    target="_blank"
                  >{{i18n "gtmc.server_status.map"}}</a>
                {{/if}}
              </div>
            {{/if}}
          </article>
        {{/each}}
      </section>
    {{/if}}
  </template>
}
