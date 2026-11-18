import Component from "@glimmer/component";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { i18n } from "discourse-i18n";
import GtmcNewcomerStepAction from "./gtmc-newcomer-step-action.gjs";

/**
 * 手机首页的新人进度卡：进度条加「下一步」。对应桌面右栏的「新人进服」面板，只显示下一步。
 * 数据还没取到时、以及四步全部完成后都不出现；桌面宽度下由样式隐藏。
 *
 * 下一步还没有去处（绑定游戏名、输入登录码要等 PLAN.md P2、P3）时只显示这句话，不放按钮：
 * 设计稿里的「去绑定」要等绑定页存在才有地方可去。
 */
export default class GtmcMobileNewcomer extends Component {
  static shouldRender(outletArgs, context) {
    return (
      context.siteSettings.gtmc_enabled &&
      !outletArgs.category &&
      !outletArgs.tag
    );
  }

  @service gtmcNewcomer;

  constructor() {
    super(...arguments);
    this.gtmcNewcomer.load();
  }

  get shouldShowCard() {
    return this.gtmcNewcomer.hasLoaded && !this.gtmcNewcomer.isComplete;
  }

  get progressTooltip() {
    return i18n("gtmc.newcomer.progress_tooltip", {
      done: this.gtmcNewcomer.doneCount,
      total: this.gtmcNewcomer.steps.length,
    });
  }

  // 整数百分比，由步数算出，不来自网络，可以安全地写进 style
  get progressWidthStyle() {
    const percent = Math.round(
      (this.gtmcNewcomer.doneCount / this.gtmcNewcomer.steps.length) * 100
    );
    return trustHTML(`width:${percent}%`);
  }

  <template>
    {{#if this.shouldShowCard}}
      <section
        aria-label={{i18n "gtmc.newcomer.title"}}
        class="gtmc-mobile-newcomer"
      >
        <h3 class="gtmc-mobile-newcomer__title">
          {{i18n "gtmc.newcomer.title"}}
          <small data-tooltip={{this.progressTooltip}}>{{this.gtmcNewcomer.doneCount}}
            /
            {{this.gtmcNewcomer.steps.length}}</small>
        </h3>
        <div class="gtmc-mobile-newcomer__progress">
          <i style={{this.progressWidthStyle}}></i>
        </div>
        <div class="gtmc-mobile-newcomer__next">
          <span>{{i18n
              "gtmc.newcomer.next_step"
              step=this.gtmcNewcomer.nextStep.label
            }}</span>
          <GtmcNewcomerStepAction @step={{this.gtmcNewcomer.nextStep}} />
        </div>
      </section>
    {{/if}}
  </template>
}
