import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcRailNewcomer from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-newcomer";

const GUIDE_URL = "/t/xin-ren-zhi-nan/12";

function respondWithGuide(body, status = 200) {
  pretender.get("/gtmc/newcomer_guide.json", () => response(status, body));
}

function stepState(key) {
  return document
    .querySelector(`.gtmc-rail-newcomer__step[data-step="${key}"]`)
    .classList.contains("is-done");
}

module("Integration | Component | GtmcRailNewcomer", function (hooks) {
  setupRenderingTest(hooks);

  test("marks registering done for a logged-in user and the guide undone until it is read", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: false });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.true(stepState("register"));
    assert.false(stepState("read_guide"));
    assert.dom(".gtmc-rail-newcomer__step").exists({ count: 4 });
    assert
      .dom(".gtmc-rail-newcomer__step[data-step='read_guide'] a")
      .hasAttribute("href", GUIDE_URL);
  });

  test("marks the guide done once the user has read it", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: true });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.true(stepState("read_guide"));
    assert
      .dom(".gtmc-rail-newcomer__step[data-step='read_guide'] a")
      .doesNotExist();
  });

  test("keeps linking and entering the login code undone until they exist", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: true });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.false(stepState("bind_mc_name"));
    assert.false(stepState("enter_login_code"));
  });

  test("shows how many steps are done", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: true });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-panel__title small").hasText("2 / 4");
    assert
      .dom(".gtmc-rail-panel__title small")
      .hasAttribute(
        "data-tooltip",
        i18n("gtmc.newcomer.progress_tooltip", { done: 2, total: 4 })
      );
  });

  test("still shows the panel, without a guide link, when the request fails", async function (assert) {
    respondWithGuide({}, 500);

    await render(<template><GtmcRailNewcomer /></template>);

    assert.dom(".gtmc-rail-newcomer").exists();
    assert.false(stepState("read_guide"));
    assert
      .dom(".gtmc-rail-newcomer__step[data-step='read_guide'] a")
      .doesNotExist();
  });

  test("shows no link when there is no pinned guide", async function (assert) {
    respondWithGuide({ topic_url: null, read: false });

    await render(<template><GtmcRailNewcomer /></template>);

    assert
      .dom(".gtmc-rail-newcomer__step[data-step='read_guide'] a")
      .doesNotExist();
  });
});

module("Integration | Component | GtmcRailNewcomer | guest", function (hooks) {
  setupRenderingTest(hooks, { anonymous: true });

  test("leaves registering undone and offers to sign up", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: false });

    await render(<template><GtmcRailNewcomer /></template>);

    assert.false(stepState("register"));
    assert.dom(".gtmc-rail-panel__title small").hasText("0 / 4");
    assert
      .dom(".gtmc-rail-newcomer__step[data-step='register'] button")
      .hasText(i18n("gtmc.newcomer.actions.sign_up"));
  });
});
