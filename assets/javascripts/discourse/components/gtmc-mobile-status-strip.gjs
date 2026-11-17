import Component from "@glimmer/component";
import { registerDestructor } from "@ember/destroyable";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * 手机首页顶部的横向服务器状态条：在线总人数 + 每个服一个小块（状态方块、服名、人数或「离线」），
 * 放不下时横向滚动。对应桌面右栏的「服务器」面板，数据来自同一个服务，不会多发请求。
 * 小块只显示结论；复制地址、玩家名单这些细节留给桌面右栏。
 *
 * 只在没有按分类或标签筛选的首页显示（shouldRender）；桌面宽度下由样式隐藏，因为那时右栏在显示同样的内容。
 */
export default class GtmcMobileStatusStrip extends Component {
  // 分类页、标签页上重复出现只是干扰。放在 shouldRender 里而不是模板里，
  // 这样不该显示时连组件和轮询都不会创建。
  static shouldRender(outletArgs, context) {
    return (
      context.siteSettings.gtmc_enabled &&
      !outletArgs.category &&
      !outletArgs.tag
    );
  }

  @service gtmcServerStatus;

  constructor() {
    super(...arguments);
    registerDestructor(this, this.gtmcServerStatus.watch());
  }

  get chips() {
    return this.gtmcServerStatus.servers.map((server) => ({
      serverId: server.server_id,
      name: server.name,
      isOnline: server.online,
      playersLabel: server.online
        ? `${server.players_online}/${server.players_max}`
        : null,
    }));
  }

  <template>
    {{#if this.gtmcServerStatus.isUnavailable}}
      <div
        class="gtmc-mobile-status-strip"
        role="status"
      ><span class="gtmc-mobile-status-strip__chip">{{i18n
            "gtmc.servers.unavailable"
          }}</span></div>
    {{else if this.gtmcServerStatus.hasServers}}
      <section
        aria-label={{i18n "gtmc.servers.title"}}
        class="gtmc-mobile-status-strip"
      >
        <span
          class="gtmc-mobile-status-strip__chip gtmc-mobile-status-strip__total"
          data-tooltip={{i18n
            "gtmc.servers.total_players_tooltip"
            count=this.gtmcServerStatus.servers.length
          }}
        >
          {{dIcon "gtmc-players"}}
          <b>{{this.gtmcServerStatus.totalPlayersOnline}}</b>
        </span>
        {{#each this.chips key="serverId" as |chip|}}
          <span
            class="gtmc-mobile-status-strip__chip
              {{unless chip.isOnline 'is-offline'}}"
            data-server-id={{chip.serverId}}
          >
            <i class="gtmc-mobile-status-strip__state"></i>
            {{chip.name}}
            {{#if chip.isOnline}}
              <span
                class="gtmc-mobile-status-strip__count"
              >{{chip.playersLabel}}</span>
            {{else}}
              <span class="gtmc-mobile-status-strip__offline">{{i18n
                  "gtmc.servers.offline"
                }}</span>
            {{/if}}
          </span>
        {{/each}}
      </section>
    {{/if}}
  </template>
}
