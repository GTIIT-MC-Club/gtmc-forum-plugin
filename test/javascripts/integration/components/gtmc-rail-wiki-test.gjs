import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import GtmcRailWiki from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-wiki";

module("Integration | Component | GtmcRailWiki", function (hooks) {
  setupRenderingTest(hooks);

  test("lists http(s) links only", async function (assert) {
    this.siteSettings.gtmc_wiki_links = JSON.stringify([
      { label: "首页", url: "https://wiki.gtmc.test/" },
      { label: "坏", url: "javascript:alert(1)" },
    ]);
    await render(<template><GtmcRailWiki /></template>);
    assert.dom(".gtmc-rail-wiki__link").exists({ count: 1 }).hasText("首页");
    assert
      .dom(".gtmc-rail-wiki__link")
      .hasAttribute("href", "https://wiki.gtmc.test/");
  });

  test("hides without usable links", async function (assert) {
    for (const value of ["[]", "", "not json", "{}"]) {
      this.siteSettings.gtmc_wiki_links = value;
      await render(<template><GtmcRailWiki /></template>);
      assert.dom(".gtmc-rail-wiki").doesNotExist();
    }
  });
});
