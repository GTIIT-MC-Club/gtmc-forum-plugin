import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import { safeMapUrl } from "../lib/gtmc-server-status-response.js";

/**
 * 右栏「Wiki」面板：gtmc_wiki_links 里的链接。一个能用的都没有时面板不出现。
 */
export default class GtmcRailWiki extends Component {
  @service siteSettings;

  // objects 类型的设置到前端是 JSON 字符串。解析失败不能抛出：渲染里的异常会让整站白屏。
  get configuredLinks() {
    try {
      const links = JSON.parse(this.siteSettings.gtmc_wiki_links);
      return Array.isArray(links) ? links : [];
    } catch {
      return [];
    }
  }

  get links() {
    return this.configuredLinks
      .map(({ label, url }) => ({ label, url: safeMapUrl(url) }))
      .filter(({ url }) => url);
  }

  <template>
    {{#if this.links.length}}
      <section
        aria-label={{i18n "gtmc.wiki.title"}}
        class="gtmc-rail-panel gtmc-rail-wiki"
      >
        <h3 class="gtmc-rail-panel__title">{{i18n "gtmc.wiki.title"}}</h3>
        <ul class="gtmc-rail-wiki__list">
          {{#each this.links as |link|}}
            <li>
              <a
                class="gtmc-rail-wiki__link"
                href={{link.url}}
                rel="noopener noreferrer"
                target="_blank"
              >{{link.label}}</a>
            </li>
          {{/each}}
        </ul>
      </section>
    {{/if}}
  </template>
}
