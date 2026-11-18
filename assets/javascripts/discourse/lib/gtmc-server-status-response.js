// status.json 的响应来自网络，进入服务的状态前先确认字段类型。任何一项不合格都当作整个接口不可用：
// 悄悄丢掉某个服会让玩家以为它不存在，比显示「状态暂不可用」更误导人。

const HTTP_URL_PATTERN = /^https?:\/\//i;
// 与后端 ServerRegistry 的 COLOR_PATTERN 一致：颜色会写进 style 属性，这里再确认一遍
const COLOR_PATTERN = /^#[0-9a-f]{6}$/i;

function isNullOr(value, predicate) {
  return value === null || predicate(value);
}

function isUsablePlayer(player) {
  return (
    typeof player?.mc_name === "string" &&
    typeof player.avatar_template === "string"
  );
}

function isUsableServer(server) {
  if (
    typeof server?.server_id !== "string" ||
    typeof server.name !== "string" ||
    typeof server.address !== "string" ||
    typeof server.icon !== "string" ||
    !isNullOr(server.color, (color) => COLOR_PATTERN.test(color)) ||
    !isNullOr(server.map_url, (mapUrl) => typeof mapUrl === "string") ||
    typeof server.online !== "boolean"
  ) {
    return false;
  }
  if (!server.online) {
    return true;
  }
  return (
    Number.isInteger(server.players_online) &&
    Number.isInteger(server.players_max) &&
    isNullOr(server.players, (players) => players.every(isUsablePlayer))
  );
}

export function isUsableStatusResponse(response) {
  return (
    Number.isInteger(response?.refresh_interval_seconds) &&
    response.refresh_interval_seconds > 0 &&
    Array.isArray(response.servers) &&
    response.servers.every(isUsableServer)
  );
}

// 站点设置没有格式校验，只放行 http(s)，免得填错成 javascript: 之类的地址被渲染成链接。
export function safeMapUrl(mapUrl) {
  return mapUrl && HTTP_URL_PATTERN.test(mapUrl) ? mapUrl : null;
}
