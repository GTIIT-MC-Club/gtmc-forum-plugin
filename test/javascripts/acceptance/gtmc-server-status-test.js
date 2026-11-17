import { click, settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import sinon from "sinon";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { i18n } from "discourse-i18n";

const OFFLINE_FIELDS = {
  online: false,
  version: null,
  players_online: null,
  players_max: null,
  player_names: null,
  tps: null,
  updated_at: null,
};

function onlineServer(serverId, name, playersOnline) {
  return {
    server_id: serverId,
    name,
    address: `${serverId}.gtmc.test`,
    map_url: `https://map.gtmc.test/${serverId}`,
    online: true,
    version: "1.21.4",
    players_online: playersOnline,
    players_max: 20,
    player_names: [],
    tps: 19.98,
    updated_at: "2026-11-17T12:00:00.000+00:00",
  };
}

function offlineServer(serverId, name) {
  return {
    server_id: serverId,
    name,
    address: `${serverId}.gtmc.test`,
    map_url: null,
    ...OFFLINE_FIELDS,
  };
}

const SURVIVAL = onlineServer("survival", "生存服", 3);

const FOUR_SERVERS = [
  SURVIVAL,
  onlineServer("creative", "创造服", 1),
  offlineServer("modded", "模组服"),
  offlineServer("minigame", "小游戏服"),
];

function cardSelector(serverId) {
  return `.gtmc-server-card[data-server-id="${serverId}"]`;
}

// 测试里的浏览器标签页未必处于可见状态，而组件的行为取决于它，所以显式指定。
function stubVisibilityState(state) {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  });
}

function restoreVisibilityState() {
  // 删掉实例上的自定义属性后，document 会回落到原型上真实的 visibilityState
  delete document.visibilityState;
}

// 每组场景只是接口响应不同，其余准备相同。
function respondWith(needs, statusResponse) {
  needs.settings({ gtmc_enabled: true });
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);
  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => statusResponse(helper));
  });
}

acceptance("GTMC server status | one server", function (needs) {
  respondWith(needs, (helper) => helper.response({ servers: [SURVIVAL] }));

  test("shows a single card with name, players, version, address and map link", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-card").exists({ count: 1 });
    const card = cardSelector("survival");
    assert.dom(card).hasClass("gtmc-server-card--online");
    assert.dom(`${card} .gtmc-server-card__name`).hasText("生存服");
    assert
      .dom(`${card} .gtmc-server-card__state`)
      .hasText(i18n("gtmc.server_status.online"));
    assert
      .dom(`${card} .gtmc-server-card__players`)
      .hasText(i18n("gtmc.server_status.players", { online: 3, max: 20 }));
    assert
      .dom(`${card} .gtmc-server-card__version`)
      .hasText(i18n("gtmc.server_status.version", { version: "1.21.4" }));
    assert
      .dom(`${card} .gtmc-server-card__address`)
      .hasText("survival.gtmc.test");
    assert
      .dom(`${card} .gtmc-server-card__map`)
      .hasAttribute("href", "https://map.gtmc.test/survival")
      .hasText(i18n("gtmc.server_status.map"));
  });

  test("is not shown on a category page", async function (assert) {
    await visit("/c/bug/1");

    assert.dom(".gtmc-server-status").doesNotExist();
  });
});

acceptance("GTMC server status | four servers", function (needs) {
  respondWith(needs, (helper) => helper.response({ servers: FOUR_SERVERS }));

  test("shows one card per server in the order of the response", async function (assert) {
    await visit("/");

    const renderedServerIds = [
      ...document.querySelectorAll(".gtmc-server-card"),
    ].map((card) => card.dataset.serverId);
    assert.deepEqual(renderedServerIds, [
      "survival",
      "creative",
      "modded",
      "minigame",
    ]);
  });

  test("shows online and offline servers side by side", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-card--online").exists({ count: 2 });
    assert.dom(".gtmc-server-card--offline").exists({ count: 2 });
    assert
      .dom(`${cardSelector("creative")} .gtmc-server-card__players`)
      .hasText(i18n("gtmc.server_status.players", { online: 1, max: 20 }));

    const offlineCard = cardSelector("modded");
    assert
      .dom(`${offlineCard} .gtmc-server-card__state`)
      .hasText(i18n("gtmc.server_status.offline"));
    assert.dom(`${offlineCard} .gtmc-server-card__players`).doesNotExist();
    assert.dom(`${offlineCard} .gtmc-server-card__address`).doesNotExist();
    assert.dom(".gtmc-server-status--unavailable").doesNotExist();
  });

  test("copies the address of the clicked server", async function (assert) {
    const writeText = sinon.stub().resolves();
    sinon.stub(window.navigator, "clipboard").get(() => ({ writeText }));

    await visit("/");
    await click(`${cardSelector("creative")} .gtmc-server-card__address`);

    assert.true(writeText.calledOnceWithExactly("creative.gtmc.test"));
  });
});

acceptance("GTMC server status | no servers", function (needs) {
  respondWith(needs, (helper) => helper.response({ servers: [] }));

  test("renders nothing when no server is registered", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status").doesNotExist();
  });
});

acceptance("GTMC server status | optional items", function (needs) {
  respondWith(needs, (helper) =>
    helper.response({
      servers: [{ ...SURVIVAL, address: "", map_url: null }],
    })
  );

  test("hides the address and the map link when they are empty", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-card--online").exists();
    assert.dom(".gtmc-server-card__address").doesNotExist();
    assert.dom(".gtmc-server-card__map").doesNotExist();
  });
});

acceptance("GTMC server status | unsafe map url", function (needs) {
  respondWith(needs, (helper) =>
    helper.response({
      servers: [
        { ...SURVIVAL, map_url: "javascript:alert(1)" }, // eslint-disable-line no-script-url
        onlineServer("creative", "创造服", 1),
      ],
    })
  );

  test("does not render a map link that is not http or https", async function (assert) {
    await visit("/");

    assert
      .dom(`${cardSelector("survival")} .gtmc-server-card__map`)
      .doesNotExist();
    assert.dom(`${cardSelector("creative")} .gtmc-server-card__map`).exists();
  });
});

acceptance("GTMC server status | request fails", function (needs) {
  respondWith(needs, (helper) => helper.response(500, {}));

  test("shows that the status is unavailable instead of a blank area", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--unavailable").exists();
    assert
      .dom(".gtmc-server-status__headline")
      .hasText(i18n("gtmc.server_status.unavailable"));
    assert.dom(".gtmc-server-card").doesNotExist();
  });
});

acceptance("GTMC server status | single-server response", function (needs) {
  // T2 时代的单服响应（没有 servers 数组），论坛和组件版本不一致时可能出现
  respondWith(needs, (helper) =>
    helper.response({ online: true, players_online: 3, players_max: 20 })
  );

  test("treats a response without a servers array as unavailable", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--unavailable").exists();
  });
});

acceptance("GTMC server status | malformed server", function (needs) {
  respondWith(needs, (helper) =>
    helper.response({
      // 在线却缺人数：不能渲染成「undefined / undefined 人」
      servers: [
        SURVIVAL,
        { ...SURVIVAL, server_id: "creative", players_max: null },
      ],
    })
  );

  test("treats a response with any malformed server as unavailable", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--unavailable").exists();
    assert.dom(".gtmc-server-card").doesNotExist();
  });
});

acceptance("GTMC server status | plugin disabled", function (needs) {
  let requestCount = 0;

  needs.settings({ gtmc_enabled: false });
  needs.hooks.beforeEach(() => {
    requestCount = 0;
    stubVisibilityState("visible");
  });
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => {
      requestCount += 1;
      return helper.response({ servers: [SURVIVAL] });
    });
  });

  test("renders nothing and does not request the status", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status").doesNotExist();
    assert.strictEqual(requestCount, 0);
  });
});

acceptance("GTMC server status | page visibility", function (needs) {
  let requestCount = 0;

  needs.settings({ gtmc_enabled: true });
  needs.hooks.beforeEach(() => {
    requestCount = 0;
  });
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => {
      requestCount += 1;
      return helper.response({ servers: [SURVIVAL] });
    });
  });

  test("does not request the status while the page is hidden", async function (assert) {
    stubVisibilityState("hidden");

    await visit("/");

    assert.strictEqual(requestCount, 0);
  });

  test("requests the status again when the page becomes visible", async function (assert) {
    stubVisibilityState("visible");
    await visit("/");
    assert.strictEqual(requestCount, 1);

    stubVisibilityState("hidden");
    document.dispatchEvent(new Event("visibilitychange"));
    await settled();
    assert.strictEqual(requestCount, 1, "hiding the page requests nothing");

    stubVisibilityState("visible");
    document.dispatchEvent(new Event("visibilitychange"));
    await settled();
    assert.strictEqual(requestCount, 2);
  });
});
