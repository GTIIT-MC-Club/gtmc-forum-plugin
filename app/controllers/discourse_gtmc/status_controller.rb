# frozen_string_literal: true

module DiscourseGtmc
  # 公开的服务器状态，右栏「服务器」面板和手机状态条按 refresh_interval_seconds 轮询。
  class StatusController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def show
      render json: ServerStatus.current(include_players: current_user.present?)
    end
  end
end
