import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import GtmcNewcomerStepAction from "./gtmc-newcomer-step-action.gjs";

/**
 * 右栏「新人进服」面板：注册、读新人指南、绑定游戏名、输入登录码四步，渲染进 gtmc-right-rail 出口。
 * 数据还没取到时、以及四步全部完成后面板都不出现。
 */
export default class GtmcRailNewcomer extends Component {
  @service gtmcNewcomer;

  constructor() {
    super(...arguments);
    this.gtmcNewcomer.load();
  }

  get shouldShowPanel() {
    return this.gtmcNewcomer.hasLoaded && !this.gtmcNewcomer.isComplete;
  }

  get progressTooltip() {
    return i18n("gtmc.newcomer.progress_tooltip", {
      done: this.gtmcNewcomer.doneCount,
      total: this.gtmcNewcomer.steps.length,
    });
  }

  <template>
    {{#if this.shouldShowPanel}}
      <section
        aria-label={{i18n "gtmc.newcomer.title"}}
        class="gtmc-rail-panel gtmc-rail-newcomer"
      >
        <h3 class="gtmc-rail-panel__title">
          {{i18n "gtmc.newcomer.title"}}
          <small data-tooltip={{this.progressTooltip}}>{{this.gtmcNewcomer.doneCount}}
            /
            {{this.gtmcNewcomer.steps.length}}</small>
        </h3>
        <ol class="gtmc-rail-newcomer__steps">
          {{#each this.gtmcNewcomer.steps key="key" as |step|}}
            <li
              class="gtmc-rail-newcomer__step {{if step.isDone "is-done"}}"
              data-step={{step.key}}
            >
              <span class="gtmc-rail-newcomer__box">
                {{#if step.isDone}}{{dIcon "check"}}{{/if}}
              </span>
              <span class="gtmc-rail-newcomer__label">{{step.label}}</span>
              <GtmcNewcomerStepAction @step={{step}} />
            </li>
          {{/each}}
        </ol>
      </section>
    {{/if}}
  </template>
}
