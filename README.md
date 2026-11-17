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

## 首页服务器状态组件

`assets/javascripts/discourse/components/gtmc-server-status.gjs`，由 `api-initializers/gtmc-server-status.js`
挂到 `discovery-above` 出口（话题列表上方）。只在没有按分类或标签筛选的列表上显示，`gtmc_enabled` 关闭时不渲染也不请求。

- 页面可见时每 30 秒请求一次 `/gtmc/status.json`；页面不可见时暂停，重新可见时立刻请求一次；组件销毁时清理。
- 三种状态：在线（人数、版本、点击复制的服务器地址、地图入口）、离线、请求失败（显示「状态暂不可用」）。
- 请求失败后不保留上一次的数据，直接显示「状态暂不可用」，避免展示过期的在线人数。
- 文案在 `config/locales/client.*.yml` 的 `js.gtmc.server_status` 下，样式在 `assets/stylesheets/gtmc-server-status.scss`。

离线的延迟：MC 服务器停止后，最迟要等到 `gtmc_heartbeat_timeout_seconds`（默认 90 秒）后接口才返回离线，
再加上组件最长 30 秒的刷新间隔，页面上最迟约 120 秒后变为离线。

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
| `gtmc_enabled` | 开 | 关掉后插件的接口返回 404；但只勾了 `gtmc:server` 的 Key 会拿到 403，因为插件关闭时 Discourse 连同它的作用域一起停用 |
| `gtmc_heartbeat_timeout_seconds` | 90 | 多久没收到心跳就算离线；MC 插件每 30 秒报一次，90 秒即连丢三次 |
| `gtmc_server_address` | 空 | 首页状态组件展示、点击即复制的服务器地址，空则不显示，后端不读 |
| `gtmc_map_url` | 空 | 首页状态组件的地图入口网址，只接受 `http(s)://` 开头的值，空或不合格则不显示，后端不读 |

## 测试

插件的 spec 跑在 Discourse 核心的测试环境里（需要 Ruby、PostgreSQL、Redis，按
[官方开发环境指南](https://meta.discourse.org/t/install-discourse-for-development/) 装好）：

```sh
# 在 Discourse 核心的检出目录里
ln -s /path/to/gtmc-discourse/plugins/discourse-gtmc plugins/discourse-gtmc
LOAD_PLUGINS=1 bin/rspec plugins/discourse-gtmc/spec
```

前端的 QUnit 验收测试在 `test/javascripts/acceptance/`，同样跑在 Discourse 核心的测试环境里
（另需 Node、pnpm 和 Chrome，按官方开发环境指南装好）：

```sh
# 在 Discourse 核心的检出目录里，插件已按上面的方式链接进 plugins/
LOAD_PLUGINS=1 bin/rake "plugin:qunit[discourse-gtmc]"
```

## 部署

生产环境由 `infra/discourse/app.yml` 的 `after_code` 钩子在重建时克隆本仓库并复制本目录进容器，
改完插件代码后在自有机器上 `./launcher rebuild app` 生效。
