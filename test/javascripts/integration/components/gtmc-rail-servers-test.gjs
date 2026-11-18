import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcRailServers from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-servers";
import {
  offlineServer,
  onlineServer,
  restoreVisibilityState,
  statusResponse,
  stubVisibilityState,
} from "../../helpers/gtmc-status-fixtures.js";

const NAMES_OF_SEVEN = ["Alex", "Bea", "Cy", "Dee", "Eli", "Fay", "Gus"];

function respondWith(body, status = 200) {
  pretender.get("/gtmc/status.json", () => response(status, body));
}

function rowOf(serverId) {
  return `.gtmc-server-row[data-server-id="${serverId}"]`;
}

function serverIdsInRows() {
  return [...document.querySelectorAll(".gtmc-server-row")].map(
    (row) => row.dataset.serverId
  );
}

module("Integration | Component | GtmcRailServers", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    stubVisibilityState("visible");
    this.siteSettings.gtmc_rail_visible_servers = 3;
  });
  hooks.afterEach(function () {
    restoreVisibilityState();
    sinon.restore();
  });

  module("order and folding", function () {
    test("shows the servers in the order the API returned them", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("creative", "创造服"),
          offlineServer("modded", "模组服"),
          onlineServer("survival", "生存服"),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.deepEqual(serverIdsInRows(), ["creative", "modded", "survival"]);
    });

    test("folds the servers beyond gtmc_rail_visible_servers behind a +N button", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服"),
          onlineServer("creative", "创造服"),
          onlineServer("minigame", "小游戏服"),
          offlineServer("modded", "模组服"),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.deepEqual(serverIdsInRows(), ["survival", "creative", "minigame"]);
      assert.dom(".gtmc-rail-servers__toggle").hasText("+1");
      assert
        .dom(".gtmc-rail-servers__toggle")
        .hasAttribute("aria-expanded", "false");
    });

    test("expands to every server and folds back on a second click", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服"),
          onlineServer("creative", "创造服"),
          onlineServer("minigame", "小游戏服"),
          offlineServer("modded", "模组服"),
        ])
      );
      await render(<template><GtmcRailServers /></template>);

      await click(".gtmc-rail-servers__toggle");

      assert.deepEqual(serverIdsInRows(), [
        "survival",
        "creative",
        "minigame",
        "modded",
      ]);
      assert
        .dom(".gtmc-rail-servers__toggle")
        .hasAttribute("aria-expanded", "true");

      await click(".gtmc-rail-servers__toggle");

      assert.dom(".gtmc-server-row").exists({ count: 3 });
    });

    test("has no +N button when every server fits", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服"),
          onlineServer("creative", "创造服"),
          onlineServer("minigame", "小游戏服"),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-server-row").exists({ count: 3 });
      assert.dom(".gtmc-rail-servers__toggle").doesNotExist();
    });

    test("follows gtmc_rail_visible_servers", async function (assert) {
      this.siteSettings.gtmc_rail_visible_servers = 1;
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服"),
          onlineServer("creative", "创造服"),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-server-row").exists({ count: 1 });
      assert.dom(".gtmc-rail-servers__toggle").hasText("+1");
    });
  });

  module("players", function () {
    test("shows five avatars and +N for the rest, with the hidden names in the tooltip", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服", { playerNames: NAMES_OF_SEVEN }),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert
        .dom(`${rowOf("survival")} .gtmc-server-row__face img`)
        .exists({ count: 5 });
      assert.dom(`${rowOf("survival")} .gtmc-server-row__more`).hasText("+2");
      assert
        .dom(`${rowOf("survival")} .gtmc-server-row__more`)
        .hasAttribute("data-tooltip", `Fay${i18n("gtmc.servers.player_separator")}Gus`);
    });

    test("shows no +N when five players or fewer are online", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服", {
            playerNames: NAMES_OF_SEVEN.slice(0, 5),
          }),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-server-row__face img").exists({ count: 5 });
      assert.dom(".gtmc-server-row__more").doesNotExist();
    });

    test("asks the avatar for the size it is shown at", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服", { playerNames: ["Alex"] }),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert
        .dom(".gtmc-server-row__face img")
        .hasAttribute("src", /\/24\.png$/);
    });

    test("shows a placeholder sentence when nobody is online", async function (assert) {
      respondWith(
        statusResponse([onlineServer("survival", "生存服", { playerNames: [] })])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-server-row__face").doesNotExist();
      assert.dom(".gtmc-server-row__placeholder").hasText(i18n("gtmc.servers.nobody_placeholder"));
      assert.dom(".gtmc-server-row__count").hasText("0/40");
    });

    test("says the server is offline in the place of the avatars", async function (assert) {
      respondWith(statusResponse([offlineServer("modded", "模组服")]));

      await render(<template><GtmcRailServers /></template>);

      assert.dom(rowOf("modded")).hasClass("gtmc-server-row--offline");
      assert.dom(".gtmc-server-row__placeholder").hasText(i18n("gtmc.servers.offline_placeholder"));
      assert.dom(".gtmc-server-row__count").hasText("—");
    });

    test("sums the players of all servers in the headline number", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服", { playersOnline: 12 }),
          onlineServer("creative", "创造服", { playersOnline: 3 }),
          offlineServer("modded", "模组服"),
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-rail-servers__total-count").hasText("15");
      assert
        .dom(".gtmc-rail-servers__total")
        .hasAttribute(
          "data-tooltip",
          i18n("gtmc.servers.total_players_tooltip", { count: 3 })
        );
    });
  });

  module("server icon and color", function () {
    test("tints the icon block with the color set in the admin and falls back to the theme accent without one", async function (assert) {
      respondWith(
        statusResponse([
          onlineServer("survival", "生存服"),
          { ...onlineServer("creative", "创造服"), color: null },
        ])
      );

      await render(<template><GtmcRailServers /></template>);

      assert
        .dom(rowOf("survival"))
        .hasAttribute("style", /--gtmc-server-color:#5dbb47/);
      assert.dom(rowOf("creative")).doesNotHaveAttribute("style");
    });

    test("draws the configured icon", async function (assert) {
      respondWith(statusResponse([onlineServer("survival", "生存服")]));

      await render(<template><GtmcRailServers /></template>);

      assert
        .dom(`${rowOf("survival")} .gtmc-server-row__icon svg`)
        .hasClass("d-icon-gtmc-bricks");
    });
  });

  module("refresh ring", function () {
    test("turns once per refresh_interval_seconds from the API, not a fixed 30 seconds", async function (assert) {
      respondWith(statusResponse([onlineServer("survival", "生存服")], 45));

      await render(<template><GtmcRailServers /></template>);

      assert
        .dom(".gtmc-refresh-ring__svg")
        .hasAttribute("style", /--gtmc-refresh-seconds:45s/);
      assert
        .dom(".gtmc-refresh-ring")
        .hasAttribute(
          "data-tooltip",
          i18n("gtmc.servers.refresh_tooltip", { seconds: 45 })
        );
    });
  });

  module("states", function () {
    test("shows the unavailable message and no ring when the request fails", async function (assert) {
      respondWith({}, 500);

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.servers.unavailable"));
      assert.dom(".gtmc-refresh-ring").doesNotExist();
      assert.dom(".gtmc-server-row").doesNotExist();
    });

    test("treats a response with a malformed server as unavailable", async function (assert) {
      respondWith(
        statusResponse([{ ...onlineServer("survival", "生存服"), color: "red" }])
      );

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.servers.unavailable"));
    });

    test("renders no panel when no server is registered", async function (assert) {
      respondWith(statusResponse([]));

      await render(<template><GtmcRailServers /></template>);

      assert.dom(".gtmc-rail-servers").doesNotExist();
    });

    test("recovers on its own after a failure", async function (assert) {
      const status = this.owner.lookup("service:gtmc-server-status");
      let requestCount = 0;
      pretender.get("/gtmc/status.json", () => {
        requestCount++;
        return requestCount === 1
          ? response(500, {})
          : response(statusResponse([onlineServer("survival", "生存服")]));
      });
      await render(<template><GtmcRailServers /></template>);
      assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.servers.unavailable"));

      await status.refresh();
      await settled();

      assert.dom(rowOf("survival")).exists();
    });
  });

  test("copies the server address and says so", async function (assert) {
    // 无头浏览器里没有写剪贴板的权限，写入本身不是这里要测的
    const writeText = sinon.stub(window.navigator.clipboard, "writeText").resolves();
    respondWith(statusResponse([onlineServer("survival", "生存服")]));
    await render(<template><GtmcRailServers /></template>);

    await click(`${rowOf("survival")} .gtmc-server-row__copy`);

    assert.true(writeText.calledOnceWith("survival.gtmc.test"));

    assert
      .dom(`${rowOf("survival")} .gtmc-server-row__copy`)
      .hasAttribute("data-tooltip", i18n("gtmc.servers.copied"));
  });

  test("links to the live map only when the map url is http(s)", async function (assert) {
    respondWith(
      statusResponse([
        onlineServer("survival", "生存服"),
        {
          ...onlineServer("creative", "创造服"),
          // eslint-disable-next-line no-script-url -- 要测的正是这种不安全的地址
          map_url: "javascript:alert(1)",
        },
        { ...onlineServer("minigame", "小游戏服"), map_url: null },
      ])
    );

    await render(<template><GtmcRailServers /></template>);

    assert
      .dom(`${rowOf("survival")} .gtmc-server-row__map`)
      .hasAttribute("href", "https://map.gtmc.test/survival");
    assert.dom(`${rowOf("creative")} .gtmc-server-row__map`).doesNotExist();
    assert.dom(`${rowOf("minigame")} .gtmc-server-row__map`).doesNotExist();
  });
});

module("Integration | Component | GtmcRailServers | guest", function (hooks) {
  setupRenderingTest(hooks, { anonymous: true });

  hooks.beforeEach(() => stubVisibilityState("visible"));
  hooks.afterEach(restoreVisibilityState);

  test("shows counts but no avatars, and says why the names are missing", async function (assert) {
    respondWith(
      statusResponse([
        onlineServer("survival", "生存服", {
          playerNames: null,
          playersOnline: 4,
        }),
      ])
    );

    await render(<template><GtmcRailServers /></template>);

    assert.dom(".gtmc-server-row__face").doesNotExist();
    assert.dom(".gtmc-server-row__count").hasText("4/40");
    assert
      .dom(".gtmc-server-row__placeholder")
      .hasText(i18n("gtmc.servers.sign_in_placeholder"));
  });

  test("shows the nobody placeholder, not the login hint, when nobody is online", async function (assert) {
    respondWith(
      statusResponse([
        onlineServer("survival", "生存服", {
          playerNames: null,
          playersOnline: 0,
        }),
      ])
    );

    await render(<template><GtmcRailServers /></template>);

    assert.dom(".gtmc-server-row__placeholder").hasText(i18n("gtmc.servers.nobody_placeholder"));
  });
});
