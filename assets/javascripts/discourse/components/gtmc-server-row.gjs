import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import { avatarUrl } from "discourse/lib/avatar-utils";
import { clipboardCopy } from "discourse/lib/utilities";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { safeMapUrl } from "../lib/gtmc-server-status-response.js";

// 头像最多叠几个，其余折成「+N」。头像叠在 5 个时一行刚好放得下 300px 宽的右栏。
const MAX_VISIBLE_AVATARS = 5;

// 「已复制」的提示停留多久；够看清，又不至于下次点的时候还在。
const COPIED_FEEDBACK_MILLIS = 1500;

// 显示的边长 24px，后端给的是 {size} 模板，按显示尺寸取图
const AVATAR_SIZE_PX = 24;

/**
 * 右栏「服务器」面板里的一行，固定两行高：
 * 第一行服名、版本、人数；第二行头像（没有时放占位文字）、地图入口和复制地址的按钮。
 * 有没有人、游客还是登录用户、在线还是离线，行高都一样。
 *
 * @param {Object} server status.json 里的一项，已通过 isUsableStatusResponse 校验
 * @param {boolean} isLoggedIn 游客看不到玩家名单，第二行放登录提示
 */
export default class GtmcServerRow extends Component {
  @tracked isAddressCopied = false;

  copiedFeedbackTimer = null;

  willDestroy() {
    super.willDestroy(...arguments);
    clearTimeout(this.copiedFeedbackTimer);
  }

  get server() {
    return this.args.server;
  }

  get stateClass() {
    return this.server.online
      ? "gtmc-server-row--online"
      : "gtmc-server-row--offline";
  }

  // color 为空时不设变量，样式里回退到主题强调色。值已在响应校验里确认是 #RRGGBB。
  get colorStyle() {
    return this.server.color
      ? trustHTML(`--gtmc-server-color:${this.server.color}`)
      : null;
  }

  get stateLabel() {
    return i18n(
      this.server.online ? "gtmc.servers.online" : "gtmc.servers.offline"
    );
  }

  get playersLabel() {
    return `${this.server.players_online}/${this.server.players_max}`;
  }

  get visiblePlayers() {
    return (this.server.players ?? [])
      .slice(0, MAX_VISIBLE_AVATARS)
      .map((player) => ({
        mcName: player.mc_name,
        avatarUrl: avatarUrl(player.avatar_template, AVATAR_SIZE_PX),
      }));
  }

  get hiddenPlayersCount() {
    return Math.max(0, (this.server.players ?? []).length - MAX_VISIBLE_AVATARS);
  }

  get hiddenPlayersTooltip() {
    return this.server.players
      .slice(MAX_VISIBLE_AVATARS)
      .map((player) => player.mc_name)
      .join(i18n("gtmc.servers.player_separator"));
  }

  // 第二行放什么：名单、或一句说明为什么没有名单。游客有人在线时不能放名单。
  get placeholderText() {
    if (!this.server.online) {
      return i18n("gtmc.servers.offline_placeholder");
    }
    if (this.server.players_online === 0) {
      return i18n("gtmc.servers.nobody_placeholder");
    }
    if (!this.args.isLoggedIn) {
      return i18n("gtmc.servers.sign_in_placeholder");
    }
    // 登录用户、有人在线，但名单为空：心跳里的名单和人数不一致，按没有名单处理
    return this.visiblePlayers.length === 0
      ? i18n("gtmc.servers.nobody_placeholder")
      : null;
  }

  get mapUrl() {
    return safeMapUrl(this.server.map_url);
  }

  get copyTooltip() {
    return this.isAddressCopied
      ? i18n("gtmc.servers.copied")
      : i18n("gtmc.servers.copy_address", { address: this.server.address });
  }

  get copyAriaLabel() {
    return i18n("gtmc.servers.copy_address_aria_label", {
      name: this.server.name,
      address: this.server.address,
    });
  }

  @action
  async copyAddress() {
    try {
      await clipboardCopy(this.server.address);
    } catch {
      // 浏览器拒绝写剪贴板（非 https、没有权限）：不改变提示，地址仍显示在按钮的悬停提示里，可以手抄
      return;
    }
    if (this.isDestroying) {
      return;
    }
    this.isAddressCopied = true;
    clearTimeout(this.copiedFeedbackTimer);
    // 不用 discourseLater：它在测试里把等待缩成 10 毫秒，测试就看不到「已复制」的状态了
    this.copiedFeedbackTimer = setTimeout(() => {
      this.isAddressCopied = false;
    }, COPIED_FEEDBACK_MILLIS);
  }

  <template>
    <div
      class="gtmc-server-row {{this.stateClass}}"
      data-server-id={{this.server.server_id}}
      style={{this.colorStyle}}
    >
      <span class="gtmc-server-row__icon">
        {{dIcon this.server.icon}}
        <i
          class="gtmc-server-row__state"
          data-tooltip={{this.stateLabel}}
        ></i>
      </span>
      <span class="gtmc-server-row__name">
        <b>{{this.server.name}}</b>
        {{#if this.server.version}}
          <span
            class="gtmc-server-row__version"
            data-tooltip={{i18n "gtmc.servers.version_tooltip"}}
          >{{this.server.version}}</span>
        {{/if}}
      </span>
      <span
        class="gtmc-server-row__count"
        data-tooltip={{if
          this.server.online
          (i18n "gtmc.servers.players_tooltip")
        }}
      >{{if this.server.online this.playersLabel "—"}}</span>
      <div class="gtmc-server-row__faces">
        {{#each this.visiblePlayers key="mcName" as |player|}}
          <span class="gtmc-server-row__face" data-tooltip={{player.mcName}}>
            <img
              alt={{player.mcName}}
              height="24"
              loading="lazy"
              src={{player.avatarUrl}}
              width="24"
            />
          </span>
        {{/each}}
        {{#if this.hiddenPlayersCount}}
          <span
            class="gtmc-server-row__more"
            data-tooltip={{this.hiddenPlayersTooltip}}
          >+{{this.hiddenPlayersCount}}</span>
        {{/if}}
        {{#if this.placeholderText}}
          <span
            class="gtmc-server-row__placeholder"
          >{{this.placeholderText}}</span>
        {{/if}}
      </div>
      <div class="gtmc-server-row__actions">
        {{#if this.mapUrl}}
          <a
            aria-label={{i18n "gtmc.servers.map"}}
            class="gtmc-icon-button gtmc-server-row__map"
            data-tooltip={{i18n "gtmc.servers.map"}}
            href={{this.mapUrl}}
            rel="noopener noreferrer"
            target="_blank"
          >{{dIcon "gtmc-compass"}}</a>
        {{/if}}
        <button
          aria-label={{this.copyAriaLabel}}
          class="gtmc-icon-button gtmc-server-row__copy"
          data-tooltip={{this.copyTooltip}}
          type="button"
          {{on "click" this.copyAddress}}
        >{{dIcon (if this.isAddressCopied "check" "gtmc-copy")}}</button>
      </div>
    </div>
  </template>
}
