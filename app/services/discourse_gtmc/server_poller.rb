# frozen_string_literal: true

module DiscourseGtmc
  # 论坛主动查询登记了 query_address 的服，结果和心跳存在同一个 Redis 键里，status.json 不区分来源。
  # 没填 query_address 的服仍然只靠心跳：两边都写会互相覆盖，查询拿不到 TPS。
  #
  # 查不到就什么也不写，过了 gtmc_heartbeat_timeout_seconds 自然显示离线。
  # 失败不记日志：服停着的时候每 30 秒一行，会刷满 /logs。
  class ServerPoller
    def self.poll_all
      ServerRegistry.servers.each do |server|
        next if server.query_host.nil?
        poll(server)
      end
    end

    def self.poll(server)
      result = MinecraftQuery.fetch(server.query_host, server.query_port)
      if result.version.blank? || result.players_online.negative? || result.players_max.negative?
        return
      end

      # 和心跳接口一样的上限，见 HeartbeatsController
      player_names =
        result
          .player_names
          .select { |name| name.length <= HeartbeatsController::MAX_MC_NAME_LENGTH }
          .first(HeartbeatsController::MAX_PLAYER_NAMES)

      ServerStatus.record_heartbeat(
        server_id: server.server_id,
        version: result.version.first(HeartbeatsController::MAX_VERSION_LENGTH),
        players_online: result.players_online,
        players_max: result.players_max,
        player_names: player_names,
        tps: nil,
      )
      refresh_favicon(server, result.host_port)
    rescue MinecraftQuery::Error
      nil
    end
    private_class_method :poll

    # 只在 Query 刚成功（服在线）、且缓存过期时才去取，免得给每次轮询再加一次超时。
    # 图标走游戏端口（Query 结果里的 hostport），不是 query.port。取失败就留着旧图标。
    def self.refresh_favicon(server, game_port)
      return if game_port.nil? || !ServerFavicon.stale?(server.server_id)
      ServerFavicon.store(
        server.server_id,
        MinecraftPing.fetch_favicon(server.query_host, game_port),
      )
    rescue MinecraftPing::Error
      nil
    end
    private_class_method :refresh_favicon
  end
end
