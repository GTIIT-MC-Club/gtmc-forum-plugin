# frozen_string_literal: true

module DiscourseGtmc
  # MC 服务器的在线状态。只保留最近一次心跳，存在 Redis 里；Redis 丢数据的后果只是
  # 在下一次心跳（默认 30 秒内）之前显示为离线。
  #
  # 在线与否在读取时按心跳的接收时间计算，而不是给 Redis 键设过期时间：
  # 这样改了 gtmc_heartbeat_timeout_seconds 立即生效，测试也能用时间冻结控制。
  class ServerStatus
    REDIS_KEY = "gtmc_server_last_heartbeat"

    OFFLINE = {
      online: false,
      version: nil,
      players_online: nil,
      players_max: nil,
      player_names: nil,
      tps: nil,
      updated_at: nil,
    }.freeze

    # 调用方负责校验参数（见 HeartbeatsController）。
    def self.record_heartbeat(version:, players_online:, players_max:, player_names:, tps:)
      heartbeat = {
        version: version,
        players_online: players_online,
        players_max: players_max,
        player_names: player_names,
        tps: tps,
        received_at: Time.zone.now.iso8601(3),
      }
      Discourse.redis.set(REDIS_KEY, heartbeat.to_json)
    end

    # 返回 PLAN.md 4.1 中 GET /gtmc/status.json 的响应体。
    def self.current
      raw_heartbeat = Discourse.redis.get(REDIS_KEY)
      return OFFLINE if raw_heartbeat.nil?

      heartbeat = JSON.parse(raw_heartbeat, symbolize_names: true)
      received_at = Time.zone.parse(heartbeat[:received_at])
      timeout_seconds = SiteSetting.gtmc_heartbeat_timeout_seconds
      return OFFLINE if received_at < timeout_seconds.seconds.ago

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
  end
end
