import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcRailNewcomer from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-newcomer";

const CHARACTER_URL = "https://skin.gtmc.test/user/player";
const JOIN_GUIDE_URL = "https://wiki.gtmc.test/server/joining";

function respondWithProgress(body, status = 200) {
  pretender.get("/gtmc/newcomer.json", () => response(status, body));
}

function isDone(key) {
  return document
    .querySelector(`.gtmc-rail-newcomer__step[data-step="${key}"]`)
    .classList.contains("is-done");
}

function stepLink(key) {
  return `.gtmc-rail-newcomer__step[data-step='${key}'] a`;
}

module("Integration | Component | GtmcRailNewcomer", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.gtmc_newcomer_character_url = CHARACTER_URL;
    this.siteSettings.gtmc_newcomer_join_guide_url = JOIN_GUIDE_URL;
  });

  test("lists three steps and links each undone one to where it is done", async function (assert) {
    respondWithProgress({
      registered: true,
      has_character: false,
      joined_server: false,
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-newcomer__step").exists({ count: 3 });
    assert.true(isDone("register"));
    assert.false(isDone("create_character"));
    assert.false(isDone("join_server"));
    assert
      .dom(stepLink("create_character"))
      .hasAttribute("href", CHARACTER_URL)
      .hasText(i18n("gtmc.newcomer.actions.create_character"));
    assert
      .dom(stepLink("join_server"))
      .hasAttribute("href", JOIN_GUIDE_URL)
      .hasText(i18n("gtmc.newcomer.actions.join_server"));
  });

  test("drops the link from a step once it is done", async function (assert) {
    respondWithProgress({
      registered: true,
      has_character: true,
      joined_server: false,
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.true(isDone("create_character"));
    assert.dom(stepLink("create_character")).doesNotExist();
    assert.dom(stepLink("join_server")).exists();
  });

  test("shows how many steps are done", async function (assert) {
    respondWithProgress({
      registered: true,
      has_character: true,
      joined_server: false,
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-panel__title small").hasText("2 / 3");
    assert
      .dom(".gtmc-rail-panel__title small")
      .hasAttribute(
        "data-tooltip",
        i18n("gtmc.newcomer.progress_tooltip", { done: 2, total: 3 })
      );
  });

  test("hides the panel once every step is done", async function (assert) {
    respondWithProgress({
      registered: true,
      has_character: true,
      joined_server: true,
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-newcomer").doesNotExist();
  });

  test("still shows the panel with only registering done when the request fails", async function (assert) {
    respondWithProgress({}, 500);

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-newcomer").exists();
    assert.true(isDone("register"));
    assert.false(isDone("create_character"));
    assert.false(isDone("join_server"));
  });

  test("shows a step without a link when its link setting is empty", async function (assert) {
    this.siteSettings.gtmc_newcomer_join_guide_url = "";
    respondWithProgress({
      registered: true,
      has_character: true,
      joined_server: false,
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.false(isDone("join_server"));
    assert.dom(stepLink("join_server")).doesNotExist();
  });
});

module("Integration | Component | GtmcRailNewcomer | guest", function (hooks) {
  setupRenderingTest(hooks, { anonymous: true });

  test("leaves every step undone and offers to sign up without asking the server", async function (assert) {
    let requested = false;
    pretender.get("/gtmc/newcomer.json", () => {
      requested = true;
      return response({});
    });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.false(requested);
    assert.dom(".gtmc-rail-panel__title small").hasText("0 / 3");
    assert
      .dom(".gtmc-rail-newcomer__step[data-step='register'] button")
      .hasText(i18n("gtmc.newcomer.actions.register"));
  });
});
