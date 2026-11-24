# frozen_string_literal: true

module DiscourseGtmc
  # 在线名单里出现过的游戏名。心跳和 Query 轮询都经过 ServerStatus.record_heartbeat，在那里记下来。
  #
  # 只记第一次：名字已经有了就跳过（ON CONFLICT DO NOTHING），所以每次心跳只有新名字真的写入。
  # 存在 PostgreSQL 而不是 Redis：「进过服」要一直算数，Redis 清空了老玩家的「新人进服」面板会重新冒出来。
  # 只有这张表上线之后出现在名单里的人才有记录。
  class SeenPlayer < ActiveRecord::Base
    self.table_name = "gtmc_seen_players"

    def self.record(server_id:, mc_names:)
      return if mc_names.empty?
      now = Time.zone.now
      rows =
        mc_names.uniq.map do |mc_name|
          { mc_name: mc_name, first_seen_at: now, first_server_id: server_id }
        end
      insert_all(rows, unique_by: :mc_name)
    end

    # 按原样比较，大小写不同不算同一个名字，理由见迁移。
    def self.any_seen?(mc_names)
      return false if mc_names.empty?
      where(mc_name: mc_names).exists?
    end
  end
end
