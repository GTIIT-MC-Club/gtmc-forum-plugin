import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// 面板里最多列几条。右栏很窄，更多的去公告版块看，标题就是去那里的链接。
const MAX_ANNOUNCEMENTS = 3;

/**
 * 右栏「公告」面板：列出 gtmc_announcement_category 版块里最新的几个话题，置顶的在前（核心列表的顺序）。
 * 读核心的版块话题列表接口，只含当前用户看得见的话题。
 *
 * 设置为空或版块不存在（被删、当前用户看不到）时整个面板不出现，也不发请求。
 * 请求失败时显示一句话，不重试：下次进入列表页会重新取。
 */
export default class GtmcRailAnnouncements extends Component {
  @service site;
  @service siteSettings;

  // null 表示还没取到；取到（或失败）后是数组，失败时为空数组并设置 hasFailed
  @tracked announcements = null;
  @tracked hasFailed = false;

  constructor() {
    super(...arguments);
    if (this.category) {
      this.loadAnnouncements();
    }
  }

  get category() {
    const categoryId = parseInt(
      this.siteSettings.gtmc_announcement_category,
      10
    );
    return this.site.categories.find((category) => category.id === categoryId);
  }

  get shouldShowPanel() {
    return this.category && this.announcements !== null;
  }

  get placeholderText() {
    if (this.hasFailed) {
      return i18n("gtmc.announcements.unavailable");
    }
    return this.announcements.length === 0
      ? i18n("gtmc.announcements.empty")
      : null;
  }

  async loadAnnouncements() {
    const category = this.category;
    let announcements;
    try {
      const response = await ajax(`${category.url}/l/latest.json`, {
        // 多取一条：版块自带的「关于」帖总在列表里，下面要去掉它
        data: { per_page: MAX_ANNOUNCEMENTS + 1 },
      });
      announcements = response.topic_list.topics
        .filter((topic) => !this.isCategoryDefinition(topic, category))
        .slice(0, MAX_ANNOUNCEMENTS)
        .map((topic) => this.toListItem(topic));
    } catch {
      this.hasFailed = true;
      announcements = [];
    }

    if (!this.isDestroying) {
      this.announcements = announcements;
    }
  }

  // 版块数据里不带「关于」帖的 id，只带它的地址 topic_url（/t/<slug>/<id>）。
  // 列表接口在指定版块时不提供排除它的参数（no_definitions 只对全站列表生效），所以在这里按地址比对。
  isCategoryDefinition(topic, category) {
    return `/t/${topic.slug}/${topic.id}` === category.topic_url;
  }

  toListItem(topic) {
    return {
      id: topic.id,
      url: `/t/${topic.slug}/${topic.id}`,
      title: topic.fancy_title ?? topic.title,
      isPinned: topic.pinned,
      dateLabel: moment(topic.created_at).format(
        i18n("gtmc.announcements.date_format")
      ),
    };
  }

  <template>
    {{#if this.shouldShowPanel}}
      <section
        aria-label={{i18n "gtmc.announcements.title"}}
        class="gtmc-rail-panel gtmc-rail-announcements"
      >
        <h3 class="gtmc-rail-panel__title">
          <a
            class="gtmc-rail-announcements__more"
            data-tooltip={{i18n "gtmc.announcements.more_tooltip"}}
            href={{this.category.url}}
          >{{i18n "gtmc.announcements.title"}}</a>
        </h3>
        {{#if this.placeholderText}}
          <p class="gtmc-rail-panel__placeholder">{{this.placeholderText}}</p>
        {{else}}
          <ul class="gtmc-rail-announcements__list">
            {{#each this.announcements key="id" as |announcement|}}
              <li>
                <a
                  class="gtmc-rail-announcements__item"
                  href={{announcement.url}}
                >
                  {{! fancy_title 由核心转义过（和话题列表一样直接输出） }}
                  <b class="gtmc-rail-announcements__name">{{trustHTML
                      announcement.title
                    }}</b>
                  <span class="gtmc-rail-announcements__meta">
                    {{! 和主题话题列表里的置顶标签同一个样式（主题的 gtmc-pinned-label.gjs） }}
                    {{#if announcement.isPinned}}
                      <span
                        class="gtmc-pinned-label gtmc-pixel-text"
                        data-tooltip={{i18n "topic_statuses.pinned.help"}}
                      >{{i18n "gtmc.announcements.pinned"}}</span>
                    {{/if}}
                    <span
                      class="gtmc-rail-announcements__when"
                    >{{announcement.dateLabel}}</span>
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
