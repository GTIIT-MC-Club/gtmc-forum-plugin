import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// 一步：key 对应 client.*.yml 的 gtmc.newcomer.steps.<key>；
// 完成与否、去哪里做都在 steps 里算好，面板和手机卡片只管显示。
// action 取值：
//   "sign_up"   打开注册窗口（只有游客的第一步有）
//   "link"      跳到 url
//   null        没有去处，只显示这一步
const STEP_KEYS = [
  "register",
  "read_guide",
  "bind_mc_name",
  "enter_login_code",
];

/**
 * 「新人进服」四步的状态：注册、读新人指南、绑定游戏名、输入登录码。
 *
 * 后两步的功能还没做（PLAN.md P2、P3），在那之前恒为未完成，也没有去处；
 * 做完后把它们的 isDone 接到各自的数据上，并给出 url。
 * 四步全部完成后面板不再出现（isComplete）。
 */
export default class GtmcNewcomerService extends Service {
  @service currentUser;

  // 接口返回的 {topic_url, read}；还没拿到时为 null
  @tracked guide = null;

  get hasLoaded() {
    return this.guide !== null;
  }

  get steps() {
    return STEP_KEYS.map((key) => this.buildStep(key));
  }

  get doneCount() {
    return this.steps.filter((step) => step.isDone).length;
  }

  get isComplete() {
    return this.doneCount === STEP_KEYS.length;
  }

  // 第一个没完成的步骤。全部完成时为 undefined，调用方应先看 isComplete。
  get nextStep() {
    return this.steps.find((step) => !step.isDone);
  }

  buildStep(key) {
    const step = {
      key,
      label: i18n(`gtmc.newcomer.steps.${key}`),
      isDone: false,
      action: null,
      actionLabel: null,
      url: null,
    };

    if (key === "register") {
      step.isDone = !!this.currentUser;
      if (!step.isDone) {
        step.action = "sign_up";
        step.actionLabel = i18n("gtmc.newcomer.actions.sign_up");
      }
    } else if (key === "read_guide") {
      step.isDone = this.guide?.read ?? false;
      if (!step.isDone && this.guide?.topic_url) {
        step.action = "link";
        step.actionLabel = i18n("gtmc.newcomer.actions.read_guide");
        step.url = this.guide.topic_url;
      }
    }
    return step;
  }

  // 面板每次出现都重新取一次：用户刚读完指南回到首页时，第二步要立刻变成已完成。
  async load() {
    let response = null;
    try {
      response = await ajax("/gtmc/newcomer_guide.json");
    } catch {
      // 取不到时按「没读过、没有指南地址」显示，面板仍然可用，只是第二步没有链接。
      // 不弹错误：这只是一份进度提示，不值得打断浏览。
    }

    if (this.isDestroying) {
      return;
    }
    const isUsable =
      typeof response?.read === "boolean" &&
      (response.topic_url === null || typeof response.topic_url === "string");
    this.guide = isUsable ? response : { topic_url: null, read: false };
  }
}
