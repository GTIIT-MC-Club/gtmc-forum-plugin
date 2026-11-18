import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcRailAnnouncements from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-announcements";

const DEFINITION_TOPIC_ID = 900;

function topic(id, title, { pinned = false, createdAt = "2026-11-18T09:00:00" } = {}) {
  return {
    id,
    slug: `topic-${id}`,
    title,
    fancy_title: title,
    pinned,
    created_at: createdAt,
  };
}

function definitionTopic() {
  return { ...topic(DEFINITION_TOPIC_ID, "关于公告版块", { pinned: true }), slug: "about-the-category" };
}

module("Integration | Component | GtmcRailAnnouncements", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    // 借用测试夹具里的第一个版块当「公告」，把它的「关于」帖地址设成已知值
    this.category = this.site.categories[0];
    this.category.topic_url = `/t/about-the-category/${DEFINITION_TOPIC_ID}`;
    this.siteSettings.gtmc_announcement_category = String(this.category.id);
    this.listUrl = `${this.category.url}/l/latest.json`;
  });

  test("lists the latest announcements as links with their date", async function (assert) {
    pretender.get(this.listUrl, () =>
      response({ topic_list: { topics: [topic(1, "服务器周六停机维护")] } })
    );

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-announcements__name").hasText("服务器周六停机维护");
    assert.dom(".gtmc-rail-announcements__item").hasAttribute("href", "/t/topic-1/1");
    assert
      .dom(".gtmc-rail-announcements__when")
      .hasText(moment("2026-11-18T09:00:00").format(i18n("gtmc.announcements.date_format")));
  });

  test("leaves out the category's own about topic", async function (assert) {
    pretender.get(this.listUrl, () =>
      response({ topic_list: { topics: [definitionTopic(), topic(1, "第一条公告")] } })
    );

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-announcements__name").exists({ count: 1 });
    assert.dom(".gtmc-rail-announcements__name").hasText("第一条公告");
  });

  test("shows at most three announcements in the order the list returned", async function (assert) {
    pretender.get(this.listUrl, () =>
      response({
        topic_list: {
          topics: [1, 2, 3, 4].map((id) => topic(id, `公告 ${id}`)),
        },
      })
    );

    await render(<template><GtmcRailAnnouncements /></template>);

    const titles = [...document.querySelectorAll(".gtmc-rail-announcements__name")].map(
      (element) => element.textContent.trim()
    );
    assert.deepEqual(titles, ["公告 1", "公告 2", "公告 3"]);
  });

  test("marks pinned announcements with the pinned label", async function (assert) {
    pretender.get(this.listUrl, () =>
      response({
        topic_list: { topics: [topic(1, "新人必读", { pinned: true }), topic(2, "普通公告")] },
      })
    );

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-pinned-label").exists({ count: 1 });
    assert.dom(".gtmc-pinned-label").hasText(i18n("gtmc.announcements.pinned"));
  });

  test("links the panel title to the announcement category", async function (assert) {
    pretender.get(this.listUrl, () => response({ topic_list: { topics: [] } }));

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-announcements__more").hasAttribute("href", this.category.url);
  });

  test("shows one placeholder sentence when the category has no announcements", async function (assert) {
    pretender.get(this.listUrl, () =>
      response({ topic_list: { topics: [definitionTopic()] } })
    );

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.announcements.empty"));
    assert.dom(".gtmc-rail-announcements__item").doesNotExist();
  });

  test("says so when the announcements cannot be loaded", async function (assert) {
    pretender.get(this.listUrl, () => response(500, {}));

    await render(<template><GtmcRailAnnouncements /></template>);

    assert
      .dom(".gtmc-rail-panel__placeholder")
      .hasText(i18n("gtmc.announcements.unavailable"));
  });

  test("renders nothing and sends no request when no category is set", async function (assert) {
    this.siteSettings.gtmc_announcement_category = "";
    let requestCount = 0;
    pretender.get(this.listUrl, () => {
      requestCount++;
      return response({ topic_list: { topics: [] } });
    });

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-announcements").doesNotExist();
    assert.strictEqual(requestCount, 0);
  });

  test("renders nothing when the set category is not visible to the user", async function (assert) {
    this.siteSettings.gtmc_announcement_category = "999999";

    await render(<template><GtmcRailAnnouncements /></template>);

    assert.dom(".gtmc-rail-announcements").doesNotExist();
  });
});
