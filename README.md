# discourse-gtmc

GTMC 论坛的 Discourse 插件：把 MC 服务器的状态接进论坛。

以 Apache-2.0 许可发布，见 [`LICENSE`](LICENSE)。论坛的部署配置和设计稿在
[gtmc-discourse-forum](https://github.com/GTIIT-MC-Club/gtmc-discourse-forum)。

## 接口

| 接口 | 谁能调 | 说明 |
|---|---|---|
| `GET /gtmc/status.json` | 任何人 | 各服的状态，右栏和手机状态条用 |
| `GET /gtmc/servers/:server_id/icon.png` | 任何人 | 服务器自己的图标（`server-icon.png`），`status.json` 的 `favicon_url` 指向它 |
| `GET /gtmc/newcomer_guide.json` | 任何人 | 新人指南帖的地址，和当前用户读过没有 |
| `PUT /gtmc/servers/:server_id/heartbeat.json` | MC 服务器（API Key） | 上报心跳 |

每个服只保留最近一次心跳，存在 Redis。Redis 清空的后果只是下一次心跳之前显示离线。

### 给 MC 服主：上报心跳

服主需要的东西只有三样：论坛地址、API Key（找论坛管理员要，见下文「给 MC 插件发 API Key」）、自己服的 `server_id`（管理员登记后告诉你）。
建议每 30 秒报一次；超过 90 秒（`gtmc_heartbeat_timeout_seconds`）没收到，论坛就显示这个服离线。

**鉴权**：每个请求带两个请求头。

| 请求头 | 值 |
|---|---|
| `Api-Key` | 管理员发给你的 Key |
| `Api-Username` | `system` |

请求体是 JSON，要带 `Content-Type: application/json`。

**请求**

```
PUT /gtmc/servers/survival/heartbeat.json
```

```sh
curl -X PUT https://forum.gtmc.top/gtmc/servers/survival/heartbeat.json \
  -H "Api-Key: $GTMC_API_KEY" \
  -H "Api-Username: system" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "1.21.4-232-ver/1.21.4",
    "players_online": 2,
    "players_max": 20,
    "player_names": ["Steve", "Alex"],
    "tps": 19.98
  }'
```

路径里的 `survival` 是你的 `server_id`。请求体字段都必须有：

| 字段 | 类型 | 说明 |
|---|---|---|
| `version` | 字符串 | 服务端版本，非空，最长 200 字符 |
| `players_online` | 整数 | 当前在线人数，不小于 0。必须是 JSON 数字，不能是 `"2"` |
| `players_max` | 整数 | 人数上限，不小于 0 |
| `player_names` | 字符串数组 | 在线玩家的游戏名，每个最长 16 字符，最多 1000 个；没人时传 `[]` |
| `tps` | 数字 | 当前 TPS，不小于 0 |

**返回**

| 状态码 | 含义 |
|---|---|
| `204 No Content` | 成功，没有响应体 |
| `400 Bad Request` | 请求体缺字段或类型不对，响应里写了是哪个字段 |
| `403 Forbidden` | 没带 Key、Key 不对、Key 没有 `gtmc:server` 范围，或 Key 的用户不是管理员 |
| `404 Not Found` | 这个 `server_id` 没有在论坛登记 |

错误响应是 JSON，形如 `{"errors": ["..."], "error_type": "invalid_parameters"}`。
插件被管理员关掉（`gtmc_enabled`）时，只勾了 `gtmc:server` 的 Key 也会得到 403，全局 Key 得到 404。
`403` 同时表示「没带 Key」和「Key 无权限」，这是 Discourse 的 API Key 机制决定的。

### 网页用的接口

`GET /gtmc/status.json`，不需要登录。登录用户还能看到在线玩家名单，游客拿到的 `players` 是 `null`（游戏名不对没登录的人公开）。

```json
{
  "refresh_interval_seconds": 30,
  "servers": [
    {
      "server_id": "survival",
      "name": "生存服",
      "address": "survival.example.com",
      "addresses": [{ "label": "外网", "address": "survival.example.com" }],
      "map_url": "https://map.example.com/survival",
      "icon": "gtmc-bricks",
      "favicon_url": "/gtmc/servers/survival/icon.png?v=2eabb7ecf3de",
      "color": "#5DBB47",
      "online": true,
      "version": "1.21.4-232-ver/1.21.4",
      "players_online": 2,
      "players_max": 20,
      "players": [{ "mc_name": "Steve", "avatar_template": "/letter_avatar_proxy/v4/letter/s/..../{size}.png" }],
      "tps": 19.98,
      "updated_at": "2026-11-19T10:00:00.000Z"
    }
  ]
}
```

`address` 是 `addresses` 的第一项，给只认一个地址的旧前端用。

在线的服排在前面，按人数从多到少，其余按登记顺序。离线的服 `online` 是 `false`，
`version`、`players_online`、`players_max`、`players`、`tps`、`updated_at` 都是 `null`。

`GET /gtmc/newcomer_guide.json` 返回 `{"topic_url": "/t/slug/12", "read": false}`，没有新人指南帖时 `topic_url` 是 `null`。

## 登记 MC 服（`gtmc_servers`）

管理后台 → 设置 → 搜索 `gtmc_servers`，这是一个对象列表（Discourse 的 `type: objects` 设置），每个服点「添加」填一项：

| 字段 | 必填 | 说明 |
|---|---|---|
| `server_id` | 是 | 1–32 个小写字母、数字或连字符，如 `survival`。必须和该服 MC 插件配置里的 `server_id` 一字不差 |
| `name` | 是 | 右栏和手机状态条上的展示名，如「生存服」 |
| `addresses` | 是 | 玩家连接用的地址，可以填好几个，每个有 `label`（如「内网」「外网」，可空）和 `address`（如 `survival.example.com`）。只有一个时右栏上点复制按钮直接复制，有多个时弹出菜单选。只用于展示 |
| `address` | 否 | 只有一个地址时的旧写法，`addresses` 为空时才用 |
| `map_url` | 否 | 实时地图的网址。留空则不显示地图入口；不以 `http://` 或 `https://` 开头的也不显示 |
| `icon` | 是 | 服务器图标。后台里是图标选择器（Discourse 的 `type: icon`），搜索 `gtmc` 能选到主题提供的像素图标（`gtmc-bricks`、`gtmc-hammer`、`gtmc-cake`、`gtmc-gear`、`gtmc-chest` 等，见 gtmc-discourse-forum 的 `design/brand/icons-8x8/`），也能选 Font Awesome 图标。选中的图标会自动进入站点的图标精灵，不用另外登记 |
| `color` | 否 | 图标颜色，`#RRGGBB`，如 `#5DBB47`。留空用主题强调色 |
| `query_address` | 否 | 论坛去查询的地址，`host:port`，如 `10.0.0.5:25581`。填了就不用装心跳插件，见下文「不装插件：论坛查询」。不对外显示 |

列表的顺序只决定离线的服、以及人数相同的服的先后：在线的服按人数从多到少排在前面。

设置的 schema 管不了 `server_id` 的格式和唯一性、`color` 的格式，所以插件读取时会**忽略**这些项：
`server_id` 格式不对、`addresses` 和 `address` 都没填、没填 `icon` 或 `icon` 不是图标名、`color` 不是 `#RRGGBB`、以及和前面某项 `server_id` 重复。
被忽略的项不出现在右栏，对应服的心跳得到 404。
保存设置时每个被忽略的项会在日志（管理后台 → 日志 → 错误日志，即 `/logs`）里记一行警告，写明原因。

**从只有四个字段的旧版升级**：已经登记的服没有 `icon`，升级后它们会被当作没登记（右栏空、心跳得到 404），
直到管理员在设置里给每一项选好图标。升级后第一件事就是去 `gtmc_servers` 补图标。

新加一个服的顺序：先在这里登记，再在那个服的插件配置里填同样的 `server_id`。顺序反过来也行，
只是登记之前那个服的心跳都会得到 404。

## 不装插件：论坛查询

填了 `query_address` 的服，论坛每 30 秒用 Minecraft 的 Query 协议（UDP）查一次，拿版本、人数和完整的在线名单，
结果和心跳存在同一处，`status.json` 看不出区别，只是 `tps` 是 `null`（Query 协议不带 TPS）。

1. 服务器的 `server.properties` 里设 `enable-query=true`，`query.port` 设一个空闲端口。它默认是 25565，不跟着 `server-port` 走，同一台机器上的几个服要各设各的。
2. 让论坛的机器能连到这个 UDP 端口：防火墙放行；服跑在 Docker 里的话要把端口映射出来。
3. 在 `gtmc_servers` 里给这个服填上 `query_address`。

注意：
- 填了 `query_address` 就别再给同一个 `server_id` 发心跳，两边会互相覆盖。
- 查不到不记日志（服停着时每 30 秒一行），过了 `gtmc_heartbeat_timeout_seconds` 显示离线。`query_address` 格式不对时，保存设置时记一行警告，这个服照常显示，只是不查询。
- 论坛重启后第一次查询最晚可能要等几分钟（mini_scheduler 的排期），之后每 30 秒一次。
- 服务器图标：查询成功后，论坛再用 Server List Ping 连游戏端口（Query 结果里的 `hostport`）取 `server-icon.png`，
  存在 Redis 里不过期，服离线时也照样显示；每小时最多重取一次。服没设图标时显示 `icon` 里选的图标。
- 代码在 `app/jobs/scheduled/gtmc_poll_servers.rb`、`app/services/discourse_gtmc/` 下的 `server_poller.rb`、`minecraft_query.rb`、`minecraft_ping.rb`、`server_favicon.rb`。

## 右栏面板和手机形态

界面按 gtmc-discourse-forum 里 `design/mockups/c-*.html` 的设计稿实现。桌面的四个面板都渲染进主题提供的
`gtmc-right-rail` 出口，只在首页和版块页（路由名以 `discovery.` 开头）出现，话题页和标签页（路由 `tag.*`）不出现；`gtmc_enabled` 关闭时不渲染也不请求。
面板按注册顺序从上到下：服务器、公告、新人进服、近期活动，入口在 `assets/javascripts/discourse/api-initializers/gtmc-right-rail.gjs`。
每个面板显示什么、什么时候不出现、失败时显示什么，见各自的组件注释。

- **服务器**（`gtmc-rail-servers.gjs`、`gtmc-server-row.gjs`）：刷新倒计时圆环、在线总人数、每个服一行；
  超过 `gtmc_rail_visible_servers` 的服折叠在「+N」按钮后面。
- **公告**（`gtmc-rail-announcements.gjs`）：`gtmc_announcement_category` 版块里最新的几个话题。
  设置由 gtmc-discourse-forum 的 `infra/discourse/sidebar.rb` 按版块名「公告」写入，不用手动填。
- **新人进服**（`gtmc-rail-newcomer.gjs`、`gtmc-newcomer-step-action.gjs`）：四步的进度，读指南用 `GET /gtmc/newcomer_guide.json`。
- **近期活动**（`gtmc-rail-events.gjs`）：读 `discourse-events` 插件的 `GET /discourse-post-event/events`，最多 3 场。
- **手机**（`gtmc-mobile-status-strip.gjs`、`gtmc-mobile-newcomer.gjs`）：挂在 `discovery-above`，横向服务器状态条加新人进度卡。

右栏和手机形态以 core 的 `lg` 断点（64rem）为界：宽于它显示右栏，窄于它显示状态条和进度卡，
两边的显示与隐藏都在 `assets/stylesheets/gtmc-rail.scss` 里。**主题的右栏出口要在同一个宽度以下隐藏。**

数据来自 `services/gtmc-server-status.js`：它是唯一的定时器，右栏面板和手机状态条共用一份轮询，
轮询约定和失败时的行为见该文件的注释；响应校验在 `lib/gtmc-server-status-response.js`。

面板里的悬停提示都写成 `data-tooltip`，由主题的全局提示服务显示；文案在 `config/locales/client.*.yml` 的 `js.gtmc` 下。
样式只用 Discourse 的 CSS 变量；`--gtmc-duration-state`、`--gtmc-ease`、`--gtmc-font-pixel` 和 `gtmc-*` 图标由主题提供。

离线的延迟：某个 MC 服停止后，最迟要等到 `gtmc_heartbeat_timeout_seconds`（默认 90 秒）后接口才返回离线，
再加上最长一个 `refresh_interval_seconds`（30 秒），页面上最迟约 120 秒后变为离线。

## 给 MC 插件发 API Key

1. 管理后台 → API 密钥 → 新建 API 密钥（菜单位置随 Discourse 版本可能变动）。
2. 「用户级别」选「单个用户」，用户填 `system`。
3. 「范围」选「精细」，只勾 `gtmc` 下的 `server`。
4. 把生成的 Key 填进 MC 插件的 `config.yml`。请求时带请求头 `Api-Key: <Key>` 和 `Api-Username: system`。

所有服可以共用这一个 Key：Key 只证明「这是我们的服」，是哪个服由请求路径里的 `server_id` 区分，`server_id` 不用于授权。

只勾了 `gtmc:server` 的 Key 访问论坛的其他任何接口都会被 Discourse 以 403 拒绝。
心跳接口还要求 Key 的用户是管理员，所以发给普通用户的 Key 即使勾了这个作用域也用不了。

## 站点设置

| 设置 | 默认 | 说明 |
|---|---|---|
| `gtmc_enabled` | 开 | 关掉后插件的接口返回 404；但只勾了 `gtmc:server` 的 Key 会拿到 403，因为插件关闭时 Discourse 连同它的作用域一起停用 |
| `gtmc_heartbeat_timeout_seconds` | 90 | 某个服多久没收到心跳就算离线；MC 插件每 30 秒报一次，90 秒即连丢三次 |
| `gtmc_servers` | 空 | 接入论坛的 MC 服，见上文「登记 MC 服」；填了 `query_address` 的由论坛定时查询 |
| `gtmc_rail_visible_servers` | 3 | 右栏「服务器」面板默认显示几个服，其余折叠在「+N」后面（1–20） |
| `gtmc_announcement_category` | 空 | 右栏「公告」面板读哪个版块；为空不显示。由 gtmc-discourse-forum 的 `infra/discourse/sidebar.rb` 写入 |

## 测试

插件的 spec 跑在 Discourse 核心的测试环境里（需要 Ruby、PostgreSQL、Redis，按
[官方开发环境指南](https://meta.discourse.org/t/install-discourse-for-development/) 装好）：

```sh
# 在 Discourse 核心的检出目录里
ln -s /path/to/gtmc-forum-plugin plugins/discourse-gtmc
LOAD_PLUGINS=1 bin/rspec plugins/discourse-gtmc/spec
```

前端的 QUnit 测试在 `test/javascripts/`（`integration/` 直接渲染各面板组件，`unit/` 测轮询服务），同样跑在 Discourse 核心的测试环境里
（另需 Node、pnpm 和 Chrome，按官方开发环境指南装好）：

```sh
# 在 Discourse 核心的检出目录里，插件已按上面的方式链接进 plugins/
LOAD_PLUGINS=1 bin/qunit --standalone --target discourse-gtmc
```

## 部署

生产环境由 gtmc-discourse-forum 里 `infra/discourse/app.yml` 的 `after_code` 钩子在重建时把本仓库克隆成容器里的 `plugins/discourse-gtmc`，
插件名 `discourse-gtmc` 和站点设置前缀 `gtmc_` 不随仓库名改变。改完插件代码合并到 `main` 后，在论坛虚拟机上
`./launcher rebuild app` 生效（后台「升级」页的 docker_manager 也能看到它落后几个提交）。
