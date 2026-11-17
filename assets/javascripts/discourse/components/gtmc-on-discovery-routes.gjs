import Component from "@glimmer/component";
import { service } from "@ember/service";

/**
 * 只在话题列表类的页面（首页、版块、标签）渲染里面的内容。
 *
 * 右栏出口在话题页也有（放话题自己的面板，见 PLAN.md T5a），服务器、新人、活动这几块不属于那里。
 * 条件放在组件里而不是 shouldRender：shouldRender 在出口渲染时算一次，不跟随路由变化。
 * 内容在条件之内才创建，所以不在列表页时它们的轮询和请求都不会启动。
 */
export default class GtmcOnDiscoveryRoutes extends Component {
  @service router;

  get isDiscoveryRoute() {
    return this.router.currentRouteName?.startsWith("discovery.");
  }

  <template>
    {{#if this.isDiscoveryRoute}}
      {{yield}}
    {{/if}}
  </template>
}
