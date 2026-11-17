# discourse-gtmc

GTMC 论坛的 Discourse 插件：把 MC 服务器的状态接进论坛，第二期起负责账号绑定和进服验证。
接口契约见仓库根目录 `PLAN.md` 第 4.1 节，代码规范见 `AGENTS.md`。

## 目前有什么（第一期）

| 接口 | 调用方 | 说明 |
|---|---|---|
| `GET /gtmc/status.json` | 任何人 | `{servers: [...]}`，`gtmc_servers` 里登记的每个服一项，顺序与设置一致；某服超过 `gtmc_heartbeat_timeout_seconds` 没收到心跳则该项 `online: false`，`version` 起的字段为 `null`；`map_url` 留空时为 `null` |
| `POST /gtmc/server/heartbeat.json` | MC 插件 | 上报 `{server_id, version, players_online, players_max, player_names[], tps}`，返回 `{status: "ok"}`；`server_id` 没登记时返回 `{status: "unknown_server"}` 且不记录 |

每个服只保留最近一次心跳，存在 Redis（键 `gtmc_server_last_heartbeat:<server_id>`）。Redis 清空的后果只是下一次心跳之前显示离线。
从 `gtmc_servers` 里删掉的服，旧键留在 Redis 里也不影响结果：读取时只看登记过的服。

心跳请求体必须是 JSON（`Content-Type: application/json`），`server_id` 必须是字符串，人数必须是非负整数、`tps` 必须是数字，
`player_names` 必须是数组（服务器没人时传 `[]`）。缺字段或类型不对返回 400。

## 登记 MC 服（`gtmc_servers`）

管理后台 → 设置 → 搜索 `gtmc_servers`，这是一个对象列表（Discourse 的 `type: objects` 设置），每个服点「添加」填一项：

| 字段 | 必填 | 说明 |
|---|---|---|
| `server_id` | 是 | 1–32 个小写字母、数字或连字符，如 `survival`。必须和该服 MC 插件配置里的 `server_id` 一字不差 |
| `name` | 是 | 首页卡片上的展示名，如「生存服」 |
| `address` | 是 | 玩家连接用的地址，如 `survival.example.com`，首页上点一下复制。只用于展示 |
| `map_url` | 否 | 实时地图的网址。留空则不显示地图入口；不以 `http://` 或 `https://` 开头的也不显示 |

列表的顺序就是首页卡片的顺序。

设置的 schema 管不了 `server_id` 的格式和唯一性，所以插件读取时会**忽略** `server_id` 格式不对的项，
以及和前面某项 `server_id` 重复的项：它们不出现在首页，对应服的心跳得到 `unknown_server`。
保存设置时每个被忽略的项会在日志（管理后台 → 日志 → 错误日志，即 `/logs`）里记一行警告。

新加一个服的顺序：先在这里登记，再在那个服的插件配置里填同样的 `server_id`。顺序反过来也行，
只是登记之前那个服的心跳都会被回 `unknown_server`。

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

所有服可以共用这一个 Key：Key 只证明「这是我们的服」，是哪个服由心跳里的 `server_id` 区分，`server_id` 不用于授权。

只勾了 `gtmc:server` 的 Key 访问论坛的其他任何接口都会被 Discourse 以 403 拒绝。
心跳接口还要求 Key 的用户是管理员，所以发给普通用户的 Key 即使勾了这个作用域也用不了。

## 站点设置

| 设置 | 默认 | 说明 |
|---|---|---|
| `gtmc_enabled` | 开 | 关掉后插件的接口返回 404；但只勾了 `gtmc:server` 的 Key 会拿到 403，因为插件关闭时 Discourse 连同它的作用域一起停用 |
| `gtmc_heartbeat_timeout_seconds` | 90 | 某个服多久没收到心跳就算离线；MC 插件每 30 秒报一次，90 秒即连丢三次 |
| `gtmc_servers` | 空 | 接入论坛的 MC 服，见上文「登记 MC 服」 |

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
