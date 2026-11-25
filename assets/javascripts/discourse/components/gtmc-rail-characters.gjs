import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import GtmcSkinViewer from "../modifiers/gtmc-skin-viewer.js";

// 后端只会给这个形状的地址；它要拼进 style，所以再核对一次
const SKIN_URL_PATTERN = /^\/gtmc\/skins\/[0-9a-f]{64}\.png$/;

/**
 * 右栏「我的角色」面板：自己在皮肤站的角色的 3D 预览，多个角色时点下面的头像切换。
 *
 * 游客、没有带皮肤的角色、请求失败时面板都不出现（建角色由「新人进服」面板引导）。
 * 画不了 3D（没有 WebGL、脚本加载失败）时显示一句话。
 */
export default class GtmcRailCharacters extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked characters = [];
  @tracked selectedName = null;
  @tracked hasViewerFailed = false;

  constructor() {
    super(...arguments);
    if (this.currentUser) {
      this.loadCharacters();
    }
  }

  get selected() {
    return (
      this.characters.find(({ name }) => name === this.selectedName) ??
      this.characters[0]
    );
  }

  get faces() {
    return this.characters.map((character) => ({
      name: character.name,
      label: i18n("gtmc.characters.switch_to", { name: character.name }),
      isSelected: character === this.selected,
      style: trustHTML(
        `background-image:url("${character.skinUrl}"),url("${character.skinUrl}")`
      ),
    }));
  }

  get hasManyCharacters() {
    return this.characters.length > 1;
  }

  async loadCharacters() {
    let characters = [];
    try {
      const response = await ajax("/gtmc/characters.json");
      characters = response.characters
        .filter(({ skin_url }) => SKIN_URL_PATTERN.test(skin_url))
        .map(({ name, slim, skin_url }) => ({
          name,
          isSlim: slim,
          skinUrl: getURL(skin_url),
        }));
    } catch {
      // 不弹错误：这只是装饰，不值得打断浏览
    }
    if (!this.isDestroying) {
      this.characters = characters;
    }
  }

  @action
  select(name) {
    this.selectedName = name;
  }

  @action
  viewerFailed() {
    if (!this.isDestroying) {
      this.hasViewerFailed = true;
    }
  }

  <template>
    {{#if this.selected}}
      <section
        aria-label={{i18n "gtmc.characters.title"}}
        class="gtmc-rail-panel gtmc-rail-characters"
      >
        <h3 class="gtmc-rail-panel__title">
          {{i18n "gtmc.characters.title"}}
          {{#if this.siteSettings.gtmc_newcomer_character_url}}
            <a
              class="gtmc-rail-characters__manage"
              href={{this.siteSettings.gtmc_newcomer_character_url}}
              rel="noopener noreferrer"
              target="_blank"
            >{{i18n "gtmc.characters.manage"}}</a>
          {{/if}}
        </h3>
        {{#if this.hasViewerFailed}}
          <p class="gtmc-rail-panel__placeholder">{{i18n
              "gtmc.characters.unavailable"
            }}</p>
        {{else}}
          <div class="gtmc-rail-characters__stage">
            <canvas
              aria-label={{i18n
                "gtmc.characters.preview"
                name=this.selected.name
              }}
              role="img"
              {{GtmcSkinViewer
                skinUrl=this.selected.skinUrl
                isSlim=this.selected.isSlim
                onError=this.viewerFailed
              }}
            ></canvas>
          </div>
        {{/if}}
        <p class="gtmc-rail-characters__name">{{this.selected.name}}</p>
        {{#if this.hasManyCharacters}}
          <div class="gtmc-rail-characters__faces">
            {{#each this.faces key="name" as |face|}}
              <button
                aria-label={{face.label}}
                aria-pressed={{if face.isSelected "true" "false"}}
                class={{dConcatClass
                  "gtmc-rail-characters__face"
                  (if face.isSelected "is-selected")
                }}
                data-tooltip={{face.name}}
                style={{face.style}}
                type="button"
                {{on "click" (fn this.select face.name)}}
              ></button>
            {{/each}}
          </div>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
