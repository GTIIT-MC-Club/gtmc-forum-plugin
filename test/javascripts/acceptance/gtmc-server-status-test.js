import { click, settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import sinon from "sinon";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { i18n } from "discourse-i18n";

const SERVER_ADDRESS = "mc.gtmc.test";
const MAP_URL = "https://map.gtmc.test";

const ONLINE_STATUS = {
  online: true,
  version: "1.21.4",
  players_online: 3,
  players_max: 20,
  player_names: ["Steve", "Alex", "Notch"],
  tps: 19.98,
  updated_at: "2026-11-17T12:00:00.000+00:00",
};

const OFFLINE_STATUS = {
  online: false,
  version: null,
  players_online: null,
  players_max: null,
  player_names: null,
  tps: null,
  updated_at: null,
};

const DEFAULT_SETTINGS = {
  gtmc_enabled: true,
  gtmc_server_address: SERVER_ADDRESS,
  gtmc_map_url: MAP_URL,
};

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

acceptance("GTMC server status | online", function (needs) {
  needs.settings(DEFAULT_SETTINGS);
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => helper.response(ONLINE_STATUS));
  });

  test("shows player count, version, address and map link", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--online").exists();
    assert
      .dom(".gtmc-server-status__headline")
      .hasText(i18n("gtmc.server_status.online"));
    assert
      .dom(".gtmc-server-status__players")
      .hasText(i18n("gtmc.server_status.players", { online: 3, max: 20 }));
    assert
      .dom(".gtmc-server-status__version")
      .hasText(i18n("gtmc.server_status.version", { version: "1.21.4" }));
    assert.dom(".gtmc-server-status__address").hasText(SERVER_ADDRESS);
    assert
      .dom(".gtmc-server-status__map")
      .hasAttribute("href", MAP_URL)
      .hasText(i18n("gtmc.server_status.map"));
  });

  test("copies the server address when the address is clicked", async function (assert) {
    const writeText = sinon.stub().resolves();
    sinon.stub(window.navigator, "clipboard").get(() => ({ writeText }));

    await visit("/");
    await click(".gtmc-server-status__address");

    assert.true(writeText.calledOnceWithExactly(SERVER_ADDRESS));
  });

  test("is not shown on a category page", async function (assert) {
    await visit("/c/bug/1");

    assert.dom(".gtmc-server-status").doesNotExist();
  });
});

acceptance("GTMC server status | optional items", function (needs) {
  needs.settings({
    ...DEFAULT_SETTINGS,
    gtmc_server_address: "",
    gtmc_map_url: "",
  });
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => helper.response(ONLINE_STATUS));
  });

  test("hides the address and the map link when their settings are empty", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--online").exists();
    assert.dom(".gtmc-server-status__address").doesNotExist();
    assert.dom(".gtmc-server-status__map").doesNotExist();
  });
});

acceptance("GTMC server status | unsafe map url", function (needs) {
  needs.settings({
    ...DEFAULT_SETTINGS,
    gtmc_map_url: "javascript:alert(1)", // eslint-disable-line no-script-url
  });
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => helper.response(ONLINE_STATUS));
  });

  test("does not render a map link that is not http or https", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--online").exists();
    assert.dom(".gtmc-server-status__map").doesNotExist();
  });
});

acceptance("GTMC server status | offline", function (needs) {
  needs.settings(DEFAULT_SETTINGS);
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => helper.response(OFFLINE_STATUS));
  });

  test("shows the server as offline without player details", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--offline").exists();
    assert
      .dom(".gtmc-server-status__headline")
      .hasText(i18n("gtmc.server_status.offline"));
    assert.dom(".gtmc-server-status__players").doesNotExist();
    assert.dom(".gtmc-server-status__address").doesNotExist();
  });
});

acceptance("GTMC server status | request fails", function (needs) {
  needs.settings(DEFAULT_SETTINGS);
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => helper.response(500, {}));
  });

  test("shows that the status is unavailable instead of a blank area", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--unavailable").exists();
    assert
      .dom(".gtmc-server-status__headline")
      .hasText(i18n("gtmc.server_status.unavailable"));
  });
});

acceptance("GTMC server status | malformed response", function (needs) {
  needs.settings(DEFAULT_SETTINGS);
  needs.hooks.beforeEach(() => stubVisibilityState("visible"));
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    // 在线却缺人数：不能渲染成「在线 undefined / undefined」
    server.get("/gtmc/status.json", () =>
      helper.response({ online: true, version: "1.21.4" })
    );
  });

  test("treats an online response without player counts as unavailable", async function (assert) {
    await visit("/");

    assert.dom(".gtmc-server-status--unavailable").exists();
  });
});

acceptance("GTMC server status | plugin disabled", function (needs) {
  let requestCount = 0;

  needs.settings({ ...DEFAULT_SETTINGS, gtmc_enabled: false });
  needs.hooks.beforeEach(() => {
    requestCount = 0;
    stubVisibilityState("visible");
  });
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => {
      requestCount += 1;
      return helper.response(ONLINE_STATUS);
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

  needs.settings(DEFAULT_SETTINGS);
  needs.hooks.beforeEach(() => {
    requestCount = 0;
  });
  needs.hooks.afterEach(restoreVisibilityState);

  needs.pretender((server, helper) => {
    server.get("/gtmc/status.json", () => {
      requestCount += 1;
      return helper.response(ONLINE_STATUS);
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
