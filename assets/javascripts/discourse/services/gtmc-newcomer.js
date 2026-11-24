import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// 一步：key 对应 client.*.yml 的 gtmc.newcomer.steps.<key> 和 actions.<key>；
// field 是 GET /gtmc/newcomer.json 里表示这一步完成与否的字段。
// 完成与否、去哪里做都在 steps 里算好，面板和手机卡片只管显示。
const STEPS = [
  { key: "register", field: "registered" },
  { key: "create_character", field: "has_character" },
  { key: "join_server", field: "joined_server" },
];

// 游客不用请求接口：三步都没完成
const GUEST_PROGRESS = Object.freeze({
  registered: false,
  has_character: false,
  joined_server: false,
});

/**
 * 「新人进服」三步的状态：注册、在皮肤站建角色、进一次服。
 * 三步都由后端判断（见 DiscourseGtmc::NewcomerProgress），全部完成后面板不再出现（isComplete）。
 *
 * 每一步的去处（action）：
 *   "sign_up"   打开注册窗口
 *   "link"      跳到 url
 * 已完成的步骤没有去处。
 */
export default class GtmcNewcomerService extends Service {
  @service currentUser;
  @service siteSettings;

  // 接口返回的 {registered, has_character, joined_server}；还没拿到时为 null
  @tracked progress = null;

  #pendingLoad = null;

  get hasLoaded() {
    return this.progress !== null;
  }

  get steps() {
    return STEPS.map((definition) => this.buildStep(definition));
  }

  get doneCount() {
    return this.steps.filter((step) => step.isDone).length;
  }

  get isComplete() {
    return this.doneCount === STEPS.length;
  }

  // 第一个没完成的步骤。全部完成时为 undefined，调用方应先看 isComplete。
  get nextStep() {
    return this.steps.find((step) => !step.isDone);
  }

  buildStep({ key, field }) {
    const isDone = this.progress?.[field] === true;
    const step = {
      key,
      label: i18n(`gtmc.newcomer.steps.${key}`),
      isDone,
      action: null,
      actionLabel: null,
      url: null,
    };
    if (isDone) {
      return step;
    }

    if (key === "register") {
      step.action = "sign_up";
    } else {
      const url =
        key === "create_character"
          ? this.siteSettings.gtmc_newcomer_character_url
          : this.siteSettings.gtmc_newcomer_join_guide_url;
      if (!url) {
        return step;
      }
      step.action = "link";
      step.url = url;
    }
    step.actionLabel = i18n(`gtmc.newcomer.actions.${key}`);
    return step;
  }

  // 面板每次出现都重新取一次：新人在皮肤站建完角色、进完服回到首页时，对应的步骤要变成已完成。
  // 右栏和手机卡片同时出现时共用同一次请求。
  load() {
    this.#pendingLoad ??= this.#fetch().finally(() => {
      this.#pendingLoad = null;
    });
    return this.#pendingLoad;
  }

  async #fetch() {
    if (!this.currentUser) {
      this.progress = GUEST_PROGRESS;
      return;
    }

    let response = null;
    try {
      response = await ajax("/gtmc/newcomer.json");
    } catch {
      // 取不到时只算「已注册」（登录了就是注册过），面板仍然可用。
      // 不弹错误：这只是一份进度提示，不值得打断浏览。
    }

    if (this.isDestroying) {
      return;
    }
    const isUsable = STEPS.every(
      ({ field }) => typeof response?.[field] === "boolean"
    );
    this.progress = isUsable
      ? response
      : { ...GUEST_PROGRESS, registered: true };
  }
}
