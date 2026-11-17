import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcMobileNewcomer from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-mobile-newcomer";
import GtmcMobileStatusStrip from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-mobile-status-strip";
import {
  offlineServer,
  onlineServer,
  restoreVisibilityState,
  statusResponse,
  stubVisibilityState,
} from "../../helpers/gtmc-status-fixtures.js";

const GUIDE_URL = "/t/xin-ren-zhi-nan/12";

function respondWithStatus(body, status = 200) {
  pretender.get("/gtmc/status.json", () => response(status, body));
}

function respondWithGuide(body) {
  pretender.get("/gtmc/newcomer_guide.json", () => response(body));
}

module("Integration | Component | GtmcMobileStatusStrip", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(() => stubVisibilityState("visible"));
  hooks.afterEach(restoreVisibilityState);

  test("shows the total and one chip per server in the order of the API", async function (assert) {
    respondWithStatus(
      statusResponse([
        onlineServer("survival", "生存服", { playersOnline: 12 }),
        onlineServer("creative", "创造服", { playersOnline: 3 }),
        offlineServer("modded", "模组服"),
      ])
    );

    await render(<template><GtmcMobileStatusStrip /></template>);

    assert.dom(".gtmc-mobile-status-strip__total b").hasText("15");
    assert.deepEqual(
      [...document.querySelectorAll("[data-server-id]")].map(
        (chip) => chip.dataset.serverId
      ),
      ["survival", "creative", "modded"]
    );
    assert
      .dom("[data-server-id='survival'] .gtmc-mobile-status-strip__count")
      .hasText("12/40");
  });

  test("marks an offline server and says so instead of showing a count", async function (assert) {
    respondWithStatus(statusResponse([offlineServer("modded", "模组服")]));

    await render(<template><GtmcMobileStatusStrip /></template>);

    assert.dom("[data-server-id='modded']").hasClass("is-offline");
    assert
      .dom("[data-server-id='modded'] .gtmc-mobile-status-strip__offline")
      .hasText(i18n("gtmc.servers.offline"));
  });

  test("says the status is unavailable when the request fails", async function (assert) {
    respondWithStatus({}, 500);

    await render(<template><GtmcMobileStatusStrip /></template>);

    assert
      .dom(".gtmc-mobile-status-strip")
      .hasText(i18n("gtmc.servers.unavailable"));
  });

  test("renders nothing when no server is registered", async function (assert) {
    respondWithStatus(statusResponse([]));

    await render(<template><GtmcMobileStatusStrip /></template>);

    assert.dom(".gtmc-mobile-status-strip").doesNotExist();
  });

  test("is only rendered on the unfiltered home list", function (assert) {
    const context = { siteSettings: { gtmc_enabled: true } };

    assert.true(GtmcMobileStatusStrip.shouldRender({}, context));
    assert.false(
      GtmcMobileStatusStrip.shouldRender({ category: { id: 1 } }, context)
    );
    assert.false(GtmcMobileStatusStrip.shouldRender({ tag: { id: 1 } }, context));
    assert.false(
      GtmcMobileStatusStrip.shouldRender(
        {},
        { siteSettings: { gtmc_enabled: false } }
      )
    );
  });
});

module("Integration | Component | GtmcMobileNewcomer", function (hooks) {
  setupRenderingTest(hooks);

  test("shows only the next step, with progress and a link to it", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: false });

    await render(<template><GtmcMobileNewcomer /></template>);

    assert.dom(".gtmc-mobile-newcomer__title small").hasText("1 / 4");
    assert
      .dom(".gtmc-mobile-newcomer__next span")
      .hasText(
        i18n("gtmc.newcomer.next_step", {
          step: i18n("gtmc.newcomer.steps.read_guide"),
        })
      );
    assert
      .dom(".gtmc-mobile-newcomer__next a")
      .hasAttribute("href", GUIDE_URL);
    assert
      .dom(".gtmc-mobile-newcomer__progress i")
      .hasAttribute("style", "width:25%");
  });

  test("moves on to linking the Minecraft name once the guide is read, without a button yet", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: true });

    await render(<template><GtmcMobileNewcomer /></template>);

    assert
      .dom(".gtmc-mobile-newcomer__next span")
      .hasText(
        i18n("gtmc.newcomer.next_step", {
          step: i18n("gtmc.newcomer.steps.bind_mc_name"),
        })
      );
    assert.dom(".gtmc-mobile-newcomer__next a").doesNotExist();
    assert.dom(".gtmc-mobile-newcomer__next button").doesNotExist();
    assert
      .dom(".gtmc-mobile-newcomer__progress i")
      .hasAttribute("style", "width:50%");
  });

  test("is only rendered on the unfiltered home list", function (assert) {
    const context = { siteSettings: { gtmc_enabled: true } };

    assert.true(GtmcMobileNewcomer.shouldRender({}, context));
    assert.false(
      GtmcMobileNewcomer.shouldRender({ category: { id: 1 } }, context)
    );
  });
});

module("Integration | Component | GtmcMobileNewcomer | guest", function (hooks) {
  setupRenderingTest(hooks, { anonymous: true });

  test("starts a guest at signing up", async function (assert) {
    respondWithGuide({ topic_url: GUIDE_URL, read: false });
    const transitionTo = sinon.stub();
    this.owner.lookup("service:router").transitionTo = transitionTo;

    await render(<template><GtmcMobileNewcomer /></template>);
    await click(".gtmc-mobile-newcomer__next button");

    assert.dom(".gtmc-mobile-newcomer__title small").hasText("0 / 4");
    assert.true(transitionTo.calledOnceWith("signup"));
  });
});
