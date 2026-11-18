import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import GtmcRefreshRing from "./gtmc-refresh-ring.gjs";
import GtmcServerRow from "./gtmc-server-row.gjs";

/**
 * 右栏「服务器」面板，渲染进主题提供的 gtmc-right-rail 出口（见 PLAN.md T5b）。
 *
 * 标题旁是刷新倒计时圆环，下面是在线总人数和每个服一行。服的顺序就是接口返回的顺序（后端排好）；
 * 超过 gtmc_rail_visible_servers 的折叠在「+N」按钮后面。
 * 没有登记任何服时整个面板不出现，免得首页上留一个空框。
 */
export default class GtmcRailServers extends Component {
  @service currentUser;
  @service gtmcServerStatus;
  @service siteSettings;

  @tracked isExpanded = false;

  constructor() {
    super(...arguments);
    registerDestructor(this, this.gtmcServerStatus.watch());
  }

  get shouldShowPanel() {
    return !this.gtmcServerStatus.hasLoaded || this.gtmcServerStatus.isUnavailable || this.gtmcServerStatus.hasServers;
  }

  get isLoggedIn() {
    return !!this.currentUser;
  }

  get hiddenServersCount() {
    return Math.max(
      0,
      this.gtmcServerStatus.servers.length -
        this.siteSettings.gtmc_rail_visible_servers
    );
  }

  get shownServers() {
    const servers = this.gtmcServerStatus.servers;
    return this.isExpanded
      ? servers
      : servers.slice(0, this.siteSettings.gtmc_rail_visible_servers);
  }

  get totalPlayersTooltip() {
    return i18n("gtmc.servers.total_players_tooltip", {
      count: this.gtmcServerStatus.servers.length,
    });
  }

  get toggleTooltip() {
    return i18n(
      this.isExpanded
        ? "gtmc.servers.collapse_tooltip"
        : "gtmc.servers.expand_tooltip"
    );
  }

  @action
  toggleExpanded() {
    this.isExpanded = !this.isExpanded;
  }

  <template>
    {{#if this.shouldShowPanel}}
      <section
        aria-label={{i18n "gtmc.servers.title"}}
        class="gtmc-rail-panel gtmc-rail-servers"
      >
        <h3 class="gtmc-rail-panel__title">
          {{i18n "gtmc.servers.title"}}
          {{#if this.gtmcServerStatus.hasLoaded}}
            {{#unless this.gtmcServerStatus.isUnavailable}}
              <GtmcRefreshRing
                @refreshCount={{this.gtmcServerStatus.refreshCount}}
                @refreshIntervalSeconds={{this.gtmcServerStatus.refreshIntervalSeconds}}
              />
            {{/unless}}
          {{/if}}
        </h3>

        {{#if this.gtmcServerStatus.isUnavailable}}
          <p class="gtmc-rail-panel__placeholder">{{i18n
              "gtmc.servers.unavailable"
            }}</p>
        {{else if this.gtmcServerStatus.hasLoaded}}
          <div
            class="gtmc-rail-servers__total"
            data-tooltip={{this.totalPlayersTooltip}}
          >
            {{dIcon "gtmc-players"}}
            <span class="gtmc-rail-servers__total-count">{{this.gtmcServerStatus.totalPlayersOnline}}</span>
          </div>
          <div class="gtmc-rail-servers__list">
            {{#each this.shownServers key="server_id" as |server|}}
              <GtmcServerRow
                @isLoggedIn={{this.isLoggedIn}}
                @server={{server}}
              />
            {{/each}}
          </div>
          {{#if this.hiddenServersCount}}
            <button
              aria-expanded={{if this.isExpanded "true" "false"}}
              class="gtmc-rail-servers__toggle {{if this.isExpanded "is-expanded"}}"
              data-tooltip={{this.toggleTooltip}}
              type="button"
              {{on "click" this.toggleExpanded}}
            >
              +{{this.hiddenServersCount}}
              {{dIcon "gtmc-chevron"}}
            </button>
          {{/if}}
        {{else}}
          <p class="gtmc-rail-panel__placeholder">{{i18n
              "gtmc.servers.loading"
            }}</p>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
