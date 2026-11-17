# discourse-gtmc

GTMC 论坛的 Discourse 插件：把 MC 服务器的状态接进论坛，第二期起负责账号绑定和进服验证。
接口契约见仓库根目录 `PLAN.md` 第 4.1 节，代码规范见 `AGENTS.md`。

## 目前有什么（第一期）

| 接口 | 调用方 | 说明 |
|---|---|---|
| `GET /gtmc/status.json` | 任何人 | `{refresh_interval_seconds, servers: [...]}`，`gtmc_servers` 里登记的每个服一项。`servers` 已排好序：在线的在前、按人数从多到少（人数相同按 `gtmc_servers` 的顺序），离线的按 `gtmc_servers` 的顺序。某服超过 `gtmc_heartbeat_timeout_seconds` 没收到心跳则该项 `online: false`，`version` 起的字段为 `null`；`map_url`、`color` 留空时为 `null`。`players` 是 `[{mc_name, avatar_template}]`，**只对登录用户返回**，游客拿到 `null`（人数照常返回），离线的服也是 `null`。P2 绑定上线前，头像都是用游戏名生成的字母头像（Discourse 自带的 `User.system_avatar_template`） |
| `GET /gtmc/newcomer_guide.json` | 任何人 | `{topic_url, read}`：置顶的、标题以「新人指南」开头的帖子（与 `infra/discourse/sidebar.rb` 的约定一致）的地址，以及当前登录用户读过它没有（读到了第一帖即算；游客恒为 `false`）。找不到或当前用户看不见时 `topic_url` 为 `null` |
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
| `name` | 是 | 右栏和手机状态条上的展示名，如「生存服」 |
| `address` | 是 | 玩家连接用的地址，如 `survival.example.com`，右栏上点复制按钮即复制。只用于展示 |
| `map_url` | 否 | 实时地图的网址。留空则不显示地图入口；不以 `http://` 或 `https://` 开头的也不显示 |
| `icon` | 是 | 服务器图标。后台里是图标选择器（Discourse 的 `type: icon`），搜索 `gtmc` 能选到主题提供的像素图标（`gtmc-bricks`、`gtmc-hammer`、`gtmc-cake`、`gtmc-gear`、`gtmc-chest` 等，见 `design/brand/icons-8x8/`），也能选 Font Awesome 图标。选中的图标会自动进入站点的图标精灵，不用另外登记 |
| `color` | 否 | 图标颜色，`#RRGGBB`，如 `#5DBB47`。留空用主题强调色 |

列表的顺序只决定离线的服、以及人数相同的服的先后：在线的服按人数从多到少排在前面。

设置的 schema 管不了 `server_id` 的格式和唯一性、`color` 的格式，所以插件读取时会**忽略**这些项：
`server_id` 格式不对、没填 `icon` 或 `icon` 不是图标名、`color` 不是 `#RRGGBB`、以及和前面某项 `server_id` 重复。
被忽略的项不出现在右栏，对应服的心跳得到 `unknown_server`。
保存设置时每个被忽略的项会在日志（管理后台 → 日志 → 错误日志，即 `/logs`）里记一行警告，写明原因。

**从只有四个字段的旧版升级**：已经登记的服没有 `icon`，升级后它们会被当作没登记（右栏空、心跳得到 `unknown_server`），
直到管理员在设置里给每一项选好图标。升级后第一件事就是去 `gtmc_servers` 补图标。

新加一个服的顺序：先在这里登记，再在那个服的插件配置里填同样的 `server_id`。顺序反过来也行，
只是登记之前那个服的心跳都会被回 `unknown_server`。

## 右栏面板和手机形态

界面按 `design/mockups/c-*.html` 实现（规则见 `AGENTS.md`「界面规则」）。桌面的三个面板都渲染进主题（T5a）提供的
`gtmc-right-rail` 出口，只在话题列表类的页面（首页、版块、标签）出现，话题页不出现；`gtmc_enabled` 关闭时不渲染也不请求。
面板按注册顺序从上到下：服务器、新人进服、近期活动，入口在 `assets/javascripts/discourse/api-initializers/gtmc-right-rail.gjs`。

- **服务器**（`gtmc-rail-servers.gjs`）：标题旁是刷新倒计时圆环，周期取接口的 `refresh_interval_seconds`；
  圆环下是在线总人数；每个服一行，固定两行高：图标块（带状态角标）、服名、版本标签、人数；
  头像叠放 5 个，其余折成 `+N`（悬停看名字），没人时放占位文字；右下是实时地图入口（有 `map_url` 时）和复制地址的按钮。
  游客拿不到玩家名单，有人在线时第二行写「登录后可看到谁在线」。
  超过 `gtmc_rail_visible_servers` 的服折叠，点「+N」展开。没有登记任何服时整个面板不出现；接口失败时显示「状态暂不可用」，不保留旧数据。
- **新人进服**（`gtmc-rail-newcomer.gjs`）：注册、读新人指南、绑定游戏名、输入登录码四步。读指南用 `GET /gtmc/newcomer_guide.json`；
  后两步在 P2、P3 做完之前恒为未完成，也没有去处，做完后改 `services/gtmc-newcomer.js` 的 `buildStep`。四步全完成后面板不再出现。
  游客也会看到：第一步「注册」未完成，旁边有「去注册」。
- **近期活动**（`gtmc-rail-events.gjs`）：读 `discourse-events` 插件的 `GET /discourse-post-event/events`
  （接口按开始时间排好序，只含当前用户看得见的活动），最多 3 场，日期块 48×48。`discourse_events_enabled`
  和 `discourse_post_event_enabled` 任一没开（或没装这个插件）时面板不出现，也不发请求；开着但没有活动时显示一句占位文字。
- **手机**（`gtmc-mobile-status-strip.gjs`、`gtmc-mobile-newcomer.gjs`）：挂在 `discovery-above`，只在没按分类或标签筛选的首页显示。
  横向服务器状态条（总人数 + 每个服的状态方块、服名、人数或「离线」）和新人进度卡（进度条 + 只显示下一步）。
  下一步还没有去处（绑定游戏名要等 P2）时只显示文字，不放按钮。

右栏和手机形态以 core 的 `lg` 断点（64rem）为界：宽于它显示右栏，窄于它显示状态条和进度卡，
两边的显示与隐藏都在 `assets/stylesheets/gtmc-rail.scss` 里。**主题的右栏出口要在同一个宽度以下隐藏。**

数据和轮询：`services/gtmc-server-status.js` 是唯一的定时器，右栏面板和手机状态条共用。有组件在看且页面可见时每
`refresh_interval_seconds` 请求一次；页面不可见时暂停，重新可见时立刻请求一次；没有组件在看时停止。
响应里任何一项不合格就整体当作不可用（`lib/gtmc-server-status-response.js`），免得悄悄丢掉某个服。
服的顺序就是接口返回的顺序，前端不再排。

面板里的悬停提示都写成 `data-tooltip`，由主题的全局提示服务显示；文案在 `config/locales/client.*.yml` 的 `js.gtmc` 下。
样式只用 Discourse 的 CSS 变量；`--gtmc-duration-state`、`--gtmc-ease`、`--gtmc-font-pixel` 和 `gtmc-*` 图标由主题提供。

离线的延迟：某个 MC 服停止后，最迟要等到 `gtmc_heartbeat_timeout_seconds`（默认 90 秒）后接口才返回离线，
再加上最长一个 `refresh_interval_seconds`（30 秒），页面上最迟约 120 秒后变为离线。

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
| `gtmc_rail_visible_servers` | 3 | 右栏「服务器」面板默认显示几个服，其余折叠在「+N」后面（1–20） |

## 测试

插件的 spec 跑在 Discourse 核心的测试环境里（需要 Ruby、PostgreSQL、Redis，按
[官方开发环境指南](https://meta.discourse.org/t/install-discourse-for-development/) 装好）：

```sh
# 在 Discourse 核心的检出目录里
ln -s /path/to/gtmc-discourse/plugins/discourse-gtmc plugins/discourse-gtmc
LOAD_PLUGINS=1 bin/rspec plugins/discourse-gtmc/spec
```

前端的 QUnit 测试在 `test/javascripts/`（`integration/` 直接渲染各面板组件，`unit/` 测轮询服务），同样跑在 Discourse 核心的测试环境里
（另需 Node、pnpm 和 Chrome，按官方开发环境指南装好）：

```sh
# 在 Discourse 核心的检出目录里，插件已按上面的方式链接进 plugins/
LOAD_PLUGINS=1 bin/qunit --standalone --target discourse-gtmc
```

## 部署

生产环境由 `infra/discourse/app.yml` 的 `after_code` 钩子在重建时克隆本仓库并复制本目录进容器，
改完插件代码后在自有机器上 `./launcher rebuild app` 生效。
