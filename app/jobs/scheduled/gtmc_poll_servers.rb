# frozen_string_literal: true

module ::Jobs
  # 每 30 秒查一遍登记了 query_address 的 MC 服，见 DiscourseGtmc::ServerPoller。
  # 30 秒和前端的刷新周期一致；gtmc_heartbeat_timeout_seconds 默认 90，连查不到三次才显示离线。
  class GtmcPollServers < ::Jobs::Scheduled
    every 30.seconds

    def execute(_args)
      return if !SiteSetting.gtmc_enabled
      DiscourseGtmc::ServerPoller.poll_all
    end
  end
end
