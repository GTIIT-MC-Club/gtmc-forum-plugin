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

    OFFLINE_FIELDS = {
      online: false,
      version: nil,
      players_online: nil,
      players_max: nil,
      player_names: nil,
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

    # 返回 PLAN.md 4.1 中 GET /gtmc/status.json 的响应体，顺序与 gtmc_servers 一致。
    def self.current
      servers =
        ServerRegistry.servers.map do |server|
          {
            server_id: server.server_id,
            name: server.name,
            address: server.address,
            map_url: server.map_url,
            **heartbeat_fields(server.server_id),
          }
        end
      { servers: servers }
    end

    # 每个服一次 GET 而不是一次 MGET：服的数量是个位数，而且 MGET 不接受零个键，
    # gtmc_servers 为空时还得单独处理。
    def self.heartbeat_fields(server_id)
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
        player_names: heartbeat[:player_names],
        tps: heartbeat[:tps],
        updated_at: heartbeat[:received_at],
      }
    end
    private_class_method :heartbeat_fields

    def self.redis_key(server_id)
      "#{REDIS_KEY_PREFIX}:#{server_id}"
    end
    private_class_method :redis_key
  end
end
