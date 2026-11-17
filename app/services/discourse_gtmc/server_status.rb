# frozen_string_literal: true

module DiscourseGtmc
  # 各 MC 服的在线状态。每个服只保留最近一次心跳，各存一个 Redis 键；Redis 丢数据的后果只是
  # 在下一次心跳（默认 30 秒内）之前显示为离线。
  #
  # 在线与否在读取时按心跳的接收时间计算，而不是给 Redis 键设过期时间：
  # 这样改了 gtmc_heartbeat_timeout_seconds 立即生效，测试也能用时间冻结控制。
  # 也因此，从 gtmc_servers 里删掉的服留下的旧键不会过期，但读取时只看登记过的服，旧键不影响结果。
  class ServerStatus
    REDIS_KEY_PREFIX = "gtmc_server_last_heartbeat"

    # 前端轮询 status.json 和刷新圆环转一圈的周期。取 MC 插件默认的心跳间隔（30 秒）：
    # 比它刷得更勤也看不到新数据。放在接口里而不是写死在前端，改它时前后端不会不一致。
    REFRESH_INTERVAL_SECONDS = 30

    OFFLINE_FIELDS = {
      online: false,
      version: nil,
      players_online: nil,
      players_max: nil,
      players: nil,
      tps: nil,
      updated_at: nil,
    }.freeze

    # 调用方负责校验参数并确认 server_id 已登记（见 HeartbeatsController）。
    def self.record_heartbeat(
      server_id:,
      version:,
      players_online:,
      players_max:,
      player_names:,
      tps:
    )
      heartbeat = {
        version: version,
        players_online: players_online,
        players_max: players_max,
        player_names: player_names,
        tps: tps,
        received_at: Time.zone.now.iso8601(3),
      }
      Discourse.redis.set(redis_key(server_id), heartbeat.to_json)
    end

    # 返回 PLAN.md 4.1 中 GET /gtmc/status.json 的响应体。
    #
    # include_players 为假（游客）时 players 为 nil，人数照常返回：玩家的游戏名是离线服里可以被冒用的身份，
    # 不对没登录的人公开。
    #
    # 排序在这里做，前端按收到的顺序显示：在线的在前、按人数从多到少，人数相同的和离线的保持
    # gtmc_servers 里的顺序。Ruby 的 sort_by 不稳定，所以用设置里的下标做第二排序键。
    def self.current(include_players:)
      entries =
        ServerRegistry.servers.map do |server|
          {
            server_id: server.server_id,
            name: server.name,
            address: server.address,
            map_url: server.map_url,
            icon: server.icon,
            color: server.color,
            **heartbeat_fields(server.server_id, include_players:),
          }
        end

      online_entries, offline_entries = entries.partition { |entry| entry[:online] }
      online_entries =
        online_entries.sort_by.with_index { |entry, index| [-entry[:players_online], index] }
      {
        refresh_interval_seconds: REFRESH_INTERVAL_SECONDS,
        servers: online_entries + offline_entries,
      }
    end

    # 每个服一次 GET 而不是一次 MGET：服的数量是个位数，而且 MGET 不接受零个键，
    # gtmc_servers 为空时还得单独处理。
    def self.heartbeat_fields(server_id, include_players:)
      raw_heartbeat = Discourse.redis.get(redis_key(server_id))
      return OFFLINE_FIELDS if raw_heartbeat.nil?

      heartbeat = JSON.parse(raw_heartbeat, symbolize_names: true)
      received_at = Time.zone.parse(heartbeat[:received_at])
      timeout_seconds = SiteSetting.gtmc_heartbeat_timeout_seconds
      return OFFLINE_FIELDS if received_at < timeout_seconds.seconds.ago

      {
        online: true,
        version: heartbeat[:version],
        players_online: heartbeat[:players_online],
        players_max: heartbeat[:players_max],
        players: include_players ? players_for(heartbeat[:player_names]) : nil,
        tps: heartbeat[:tps],
        updated_at: heartbeat[:received_at],
      }
    end
    private_class_method :heartbeat_fields

    # P2 绑定上线前，所有玩家都用游戏名生成字母头像；绑定后改用对应论坛账号的头像（PLAN.md 4.1）。
    # 用 User.system_avatar_template 而不是自己画：它遵循站点的头像设置，返回的模板里留着 {size}，
    # 前端按显示尺寸替换。不用 default_template：它会优先返回管理员配置的默认头像，
    # 那样所有玩家就是同一张图。
    def self.players_for(player_names)
      player_names.map do |mc_name|
        { mc_name: mc_name, avatar_template: User.system_avatar_template(mc_name) }
      end
    end
    private_class_method :players_for

    def self.redis_key(server_id)
      "#{REDIS_KEY_PREFIX}:#{server_id}"
    end
    private_class_method :redis_key
  end
end
