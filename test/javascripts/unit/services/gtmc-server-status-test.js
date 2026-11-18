import { settled } from "@ember/test-helpers";
import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import sinon from "sinon";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import {
  onlineServer,
  restoreVisibilityState,
  statusResponse,
  stubVisibilityState,
} from "../../helpers/gtmc-status-fixtures.js";

function respondWith(body, status = 200) {
  pretender.get("/gtmc/status.json", () => response(status, body));
}

module("Unit | Service | gtmc-server-status", function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(function () {
    stubVisibilityState("visible");
    this.timeouts = sinon.spy(window, "setTimeout");
  });
  hooks.afterEach(function () {
    restoreVisibilityState();
    sinon.restore();
  });

  test("schedules the next request after refresh_interval_seconds from the response", async function (assert) {
    respondWith(statusResponse([onlineServer("survival", "生存服")], 45));
    const service = this.owner.lookup("service:gtmc-server-status");

    const stopWatching = service.watch();
    await settled();

    assert.true(
      this.timeouts.calledWith(sinon.match.func, 45_000),
      "setTimeout was called with 45000 milliseconds"
    );
    stopWatching();
  });

  test("stops polling once nobody is watching", async function (assert) {
    respondWith(statusResponse([onlineServer("survival", "生存服")]));
    const service = this.owner.lookup("service:gtmc-server-status");
    const stopWatching = service.watch();
    await settled();
    const clearTimeouts = sinon.spy(window, "clearTimeout");

    stopWatching();

    assert.true(clearTimeouts.called);
    assert.strictEqual(service.watcherCount, 0);
  });

  test("keeps polling while another component still watches", async function (assert) {
    respondWith(statusResponse([onlineServer("survival", "生存服")]));
    const service = this.owner.lookup("service:gtmc-server-status");
    const stopFirst = service.watch();
    const stopSecond = service.watch();
    await settled();

    stopFirst();
    stopFirst();

    assert.strictEqual(service.watcherCount, 1);
    stopSecond();
  });

  test("does not request while the page is hidden", async function (assert) {
    stubVisibilityState("hidden");
    let requestCount = 0;
    pretender.get("/gtmc/status.json", () => {
      requestCount++;
      return response(statusResponse([]));
    });
    const service = this.owner.lookup("service:gtmc-server-status");

    const stopWatching = service.watch();
    await settled();

    assert.strictEqual(requestCount, 0);
    stopWatching();
  });

  test("falls back to its own interval when the first request fails", async function (assert) {
    respondWith({}, 500);
    const service = this.owner.lookup("service:gtmc-server-status");

    const stopWatching = service.watch();
    await settled();

    assert.true(service.isUnavailable);
    assert.true(this.timeouts.calledWith(sinon.match.func, 30_000));
    stopWatching();
  });
});
