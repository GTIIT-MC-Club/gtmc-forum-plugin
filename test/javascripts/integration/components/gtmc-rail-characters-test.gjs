import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import GtmcRailCharacters from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-characters";

const PANEL = ".gtmc-rail-characters";
const NAME = ".gtmc-rail-characters__name";
const FACE = ".gtmc-rail-characters__face";

function character(name) {
  return {
    name,
    slim: false,
    skin_url: `/gtmc/skins/${"a".repeat(64)}.png`,
  };
}

function respondWith(characters) {
  pretender.get("/gtmc/characters.json", () => response({ characters }));
}

module("Integration | Component | GtmcRailCharacters", function (hooks) {
  setupRenderingTest(hooks);

  test("shows one character without a switcher", async function (assert) {
    respondWith([character("Steve")]);
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(NAME).hasText("Steve");
    assert.dom(FACE).doesNotExist();
  });

  test("switches between characters", async function (assert) {
    respondWith([character("Steve"), character("Alex")]);
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(FACE).exists({ count: 2 });

    await click(`${FACE}[data-tooltip="Alex"]`);
    await settled();

    assert.dom(NAME).hasText("Alex");
    assert.dom(`${FACE}[data-tooltip="Alex"]`).hasAria("pressed", "true");
  });

  test("hides without characters, on failure and for odd skin URLs", async function (assert) {
    respondWith([]);
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(PANEL).doesNotExist();

    respondWith([{ ...character("Steve"), skin_url: "https://evil.test/a" }]);
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(PANEL).doesNotExist();

    pretender.get("/gtmc/characters.json", () => response(500, {}));
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(PANEL).doesNotExist();
  });
});

module("Integration | Component | GtmcRailCharacters | guest", function (hooks) {
  setupRenderingTest(hooks, { anonymous: true });

  test("does not ask the server", async function (assert) {
    await render(<template><GtmcRailCharacters /></template>);
    assert.dom(PANEL).doesNotExist();
  });
});
