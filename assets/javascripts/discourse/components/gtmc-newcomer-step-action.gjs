import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";

/**
 * 一步的去处：注册打开注册窗口，读指南是个站内链接，没有去处的步骤什么都不渲染。
 * 站内链接用普通的 <a href>：Discourse 会拦截站内链接的点击并走前端路由。
 *
 * @param {Object} step GtmcNewcomerService.steps 里的一项
 */
export default class GtmcNewcomerStepAction extends Component {
  @service router;

  @action
  signUp() {
    this.router.transitionTo("signup");
  }

  <template>
    {{#if @step.action}}
      {{#if @step.url}}
        <a class="gtmc-newcomer-action" href={{@step.url}}>{{@step.actionLabel}}</a>
      {{else}}
        <button
          class="gtmc-newcomer-action"
          type="button"
          {{on "click" this.signUp}}
        >{{@step.actionLabel}}</button>
      {{/if}}
    {{/if}}
  </template>
}
