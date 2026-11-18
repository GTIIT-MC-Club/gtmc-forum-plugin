import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// 面板里最多列几场。右栏很窄，3 场之后就是「看更多」的事了，那是活动日历页的职责。
const MAX_EVENTS = 3;

// 只看这么远的活动：再往后的活动离「近期」太远，也避免把一年后的例会排在面板里
const UPCOMING_DAYS = 90;

/**
 * 右栏「近期活动」面板，读 discourse-events 插件的活动列表
 * （GET /discourse-post-event/events，接口按开始时间从早到晚返回，只含当前用户看得见的活动）。
 *
 * discourse_events_enabled 和 discourse_post_event_enabled 任一没开（或插件没装）时整个面板不出现，
 * 也不发请求。开着但近期没有活动时显示一句占位文字；请求失败时也是一句话，不重试：
 * 这块是辅助信息，下次进入列表页会重新取。
 */
export default class GtmcRailEvents extends Component {
  @service siteSettings;

  // null 表示还没取到；取到（或失败）后是数组，失败时为空数组并设置 hasFailed
  @tracked events = null;
  @tracked hasFailed = false;

  constructor() {
    super(...arguments);
    if (this.isEventsPluginEnabled) {
      this.loadEvents();
    }
  }

  get isEventsPluginEnabled() {
    return (
      this.siteSettings.discourse_events_enabled &&
      this.siteSettings.discourse_post_event_enabled
    );
  }

  get shouldShowPanel() {
    return this.isEventsPluginEnabled && this.events !== null;
  }

  get placeholderText() {
    if (this.hasFailed) {
      return i18n("gtmc.events.unavailable");
    }
    return this.events.length === 0 ? i18n("gtmc.events.empty") : null;
  }

  async loadEvents() {
    const now = moment();
    let events;
    try {
      const response = await ajax("/discourse-post-event/events", {
        data: {
          limit: MAX_EVENTS,
          after: now.toISOString(),
          before: now.clone().add(UPCOMING_DAYS, "days").toISOString(),
          include_ongoing: true,
        },
      });
      events = response.events.map((event) => this.toListItem(event, now));
    } catch {
      this.hasFailed = true;
      events = [];
    }

    if (!this.isDestroying) {
      this.events = events;
    }
  }

  // 已经开始、还没结束的多天活动，日期块显示今天，免得「进行中」的活动显示成过去的日子
  toListItem(event, now) {
    const startsAt = moment(event.starts_at);
    const shownDate = startsAt.isBefore(now, "day") ? now : startsAt;
    return {
      id: event.id,
      url: event.post.url,
      name: event.name || event.post.topic.title,
      day: shownDate.format("DD"),
      dateLabel: shownDate.format(i18n("gtmc.events.date_format")),
    };
  }

  <template>
    {{#if this.shouldShowPanel}}
      <section
        aria-label={{i18n "gtmc.events.title"}}
        class="gtmc-rail-panel gtmc-rail-events"
      >
        <h3 class="gtmc-rail-panel__title">{{i18n "gtmc.events.title"}}</h3>
        {{#if this.placeholderText}}
          <p class="gtmc-rail-panel__placeholder">{{this.placeholderText}}</p>
        {{else}}
          <ul class="gtmc-rail-events__list">
            {{#each this.events key="id" as |event|}}
              <li>
                <a class="gtmc-rail-events__item" href={{event.url}}>
                  <span class="gtmc-rail-events__date">{{event.day}}</span>
                  <span class="gtmc-rail-events__text">
                    <b class="gtmc-rail-events__name">{{event.name}}</b>
                    <span
                      class="gtmc-rail-events__when"
                    >{{event.dateLabel}}</span>
                  </span>
                </a>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
