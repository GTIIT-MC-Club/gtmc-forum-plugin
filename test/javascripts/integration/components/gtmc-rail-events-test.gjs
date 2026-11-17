import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import GtmcRailEvents from "discourse/plugins/discourse-gtmc/discourse/components/gtmc-rail-events";

function event(id, name, startsAt) {
  return {
    id,
    name,
    starts_at: startsAt,
    ends_at: null,
    post: {
      url: `/t/event-${id}/${id}/1`,
      topic: { title: `话题标题 ${id}` },
    },
  };
}

module("Integration | Component | GtmcRailEvents", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.discourse_events_enabled = true;
    this.siteSettings.discourse_post_event_enabled = true;
    // 只冻结 Date：把整套定时器都换掉会让 Ember 的等待机制失效
    this.clock = sinon.useFakeTimers({
      now: new Date("2026-12-01T09:00:00"),
      toFake: ["Date"],
    });
  });
  hooks.afterEach(function () {
    this.clock.restore();
  });

  test("shows each event with a 48 by 48 date block and its title as a link", async function (assert) {
    pretender.get("/discourse-post-event/events", () =>
      response({ events: [event(7, "建筑大赛「海港」报名截止", "2026-12-06T10:00:00")] })
    );

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events__date").hasText("06");
    assert.dom(".gtmc-rail-events__name").hasText("建筑大赛「海港」报名截止");
    assert.dom(".gtmc-rail-events__item").hasAttribute("href", "/t/event-7/7/1");
    assert
      .dom(".gtmc-rail-events__when")
      .hasText(moment("2026-12-06T10:00:00").format(i18n("gtmc.events.date_format")));
  });

  test("falls back to the topic title for an event without a name", async function (assert) {
    pretender.get("/discourse-post-event/events", () =>
      response({ events: [event(8, null, "2026-12-06T10:00:00")] })
    );

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events__name").hasText("话题标题 8");
  });

  test("keeps the order the events plugin returned", async function (assert) {
    pretender.get("/discourse-post-event/events", () =>
      response({
        events: [
          event(1, "第一场", "2026-12-03T10:00:00"),
          event(2, "第二场", "2026-12-05T10:00:00"),
        ],
      })
    );

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events__name").exists({ count: 2 });
    assert.strictEqual(
      document.querySelectorAll(".gtmc-rail-events__name")[0].textContent.trim(),
      "第一场"
    );
  });

  test("shows today in the date block for an event that has already started", async function (assert) {
    pretender.get("/discourse-post-event/events", () =>
      response({ events: [event(3, "长期活动", "2026-11-20T10:00:00")] })
    );

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events__date").hasText("01");
  });

  test("asks only for upcoming and ongoing events and caps the list", async function (assert) {
    let query;
    pretender.get("/discourse-post-event/events", (request) => {
      query = request.queryParams;
      return response({ events: [] });
    });

    await render(<template><GtmcRailEvents /></template>);

    assert.strictEqual(query.limit, "3");
    assert.strictEqual(query.include_ongoing, "true");
    assert.true(!!query.after, "has a lower bound");
    assert.true(!!query.before, "has an upper bound");
  });

  test("shows one placeholder sentence when there are no upcoming events", async function (assert) {
    pretender.get("/discourse-post-event/events", () => response({ events: [] }));

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.events.empty"));
    assert.dom(".gtmc-rail-events__item").doesNotExist();
  });

  test("says so when the events cannot be loaded", async function (assert) {
    pretender.get("/discourse-post-event/events", () => response(500, {}));

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-panel__placeholder").hasText(i18n("gtmc.events.unavailable"));
  });

  test("renders nothing and sends no request when the events plugin is off", async function (assert) {
    this.siteSettings.discourse_post_event_enabled = false;
    let requestCount = 0;
    pretender.get("/discourse-post-event/events", () => {
      requestCount++;
      return response({ events: [] });
    });

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events").doesNotExist();
    assert.strictEqual(requestCount, 0);
  });

  test("renders nothing when the events plugin is not installed at all", async function (assert) {
    delete this.siteSettings.discourse_events_enabled;
    delete this.siteSettings.discourse_post_event_enabled;

    await render(<template><GtmcRailEvents /></template>);

    assert.dom(".gtmc-rail-events").doesNotExist();
  });
});
