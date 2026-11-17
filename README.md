# discourse-gtmc

GTMC 论坛的 Discourse 插件：把 MC 服务器的状态接进论坛，第二期起负责账号绑定和进服验证。
接口契约见仓库根目录 `PLAN.md` 第 4.1 节，代码规范见 `AGENTS.md`。

## 目前有什么（第一期）

| 接口 | 调用方 | 说明 |
|---|---|---|
| `GET /gtmc/status.json` | 任何人 | 最近一次心跳的内容；超过 `gtmc_heartbeat_timeout_seconds` 没收到心跳则 `online: false`，其余字段为 `null` |
| `POST /gtmc/server/heartbeat.json` | MC 插件 | 上报 `{version, players_online, players_max, player_names[], tps}`，返回 `{status: "ok"}` |

心跳只保留最近一次，存在 Redis（键 `gtmc_server_last_heartbeat`）。Redis 清空的后果只是下一次心跳之前显示离线。

心跳请求体必须是 JSON（`Content-Type: application/json`），人数必须是非负整数、`tps` 必须是数字，
`player_names` 必须是数组（服务器没人时传 `[]`）。类型不对返回 400。

## 给 MC 插件发 API Key

1. 管理后台 → API 密钥 → 新建 API 密钥（菜单位置随 Discourse 版本可能变动）。
2. 「用户级别」选「单个用户」，用户填 `system`。
3. 「范围」选「精细」，只勾 `gtmc` 下的 `server`。
4. 把生成的 Key 填进 MC 插件的 `config.yml`。请求时带请求头 `Api-Key: <Key>` 和 `Api-Username: system`。

只勾了 `gtmc:server` 的 Key 访问论坛的其他任何接口都会被 Discourse 以 403 拒绝。
心跳接口还要求 Key 的用户是管理员，所以发给普通用户的 Key 即使勾了这个作用域也用不了。

## 站点设置

| 设置 | 默认 | 说明 |
|---|---|---|
| `gtmc_enabled` | 开 | 关掉后插件的所有接口返回 404 |
| `gtmc_heartbeat_timeout_seconds` | 90 | 多久没收到心跳就算离线；MC 插件每 30 秒报一次，90 秒即连丢三次 |
| `gtmc_server_address` | 空 | 首页状态组件展示的服务器地址，后端不读 |
| `gtmc_map_url` | 空 | 地图入口网址，空则不显示，后端不读 |

## 测试

插件的 spec 跑在 Discourse 核心的测试环境里（需要 Ruby、PostgreSQL、Redis，按
[官方开发环境指南](https://meta.discourse.org/t/install-discourse-for-development/) 装好）：

```sh
# 在 Discourse 核心的检出目录里
ln -s /path/to/gtmc-discourse/plugins/discourse-gtmc plugins/discourse-gtmc
LOAD_PLUGINS=1 bin/rspec plugins/discourse-gtmc/spec
```

## 部署

生产环境由 `infra/discourse/app.yml` 的 `after_code` 钩子在重建时克隆本仓库并复制本目录进容器，
改完插件代码后在自有机器上 `./launcher rebuild app` 生效。
