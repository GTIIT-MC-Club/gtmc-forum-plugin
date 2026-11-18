// status.json 的假数据，形状见 PLAN.md 4.1。

export const OFFLINE_FIELDS = {
  online: false,
  version: null,
  players_online: null,
  players_max: null,
  players: null,
  tps: null,
  updated_at: null,
};

export function player(mcName) {
  return {
    mc_name: mcName,
    avatar_template: `/letter_avatar_proxy/v4/letter/${mcName[0].toLowerCase()}/aabbcc/{size}.png`,
  };
}

// playerNames 为 null 表示游客：人数照常，名单没有
export function onlineServer(
  serverId,
  name,
  { playerNames, playersOnline } = {}
) {
  const players = playerNames === null ? null : (playerNames ?? []).map(player);
  return {
    server_id: serverId,
    name,
    address: `${serverId}.gtmc.test`,
    map_url: `https://map.gtmc.test/${serverId}`,
    icon: "gtmc-bricks",
    color: "#5dbb47",
    online: true,
    version: "1.21.4",
    players_online: playersOnline ?? players?.length ?? 0,
    players_max: 40,
    players,
    tps: 19.98,
    updated_at: "2026-11-17T12:00:00.000+00:00",
  };
}

export function offlineServer(serverId, name) {
  return {
    server_id: serverId,
    name,
    address: `${serverId}.gtmc.test`,
    map_url: null,
    icon: "gtmc-gear",
    color: null,
    ...OFFLINE_FIELDS,
  };
}

export function statusResponse(servers, refreshIntervalSeconds = 30) {
  return { refresh_interval_seconds: refreshIntervalSeconds, servers };
}

// 测试里的浏览器标签页未必处于可见状态，而轮询的行为取决于它，所以显式指定。
export function stubVisibilityState(state) {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  });
}

export function restoreVisibilityState() {
  // 删掉实例上的自定义属性后，document 会回落到原型上真实的 visibilityState
  delete document.visibilityState;
}
