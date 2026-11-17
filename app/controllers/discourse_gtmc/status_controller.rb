# frozen_string_literal: true

module DiscourseGtmc
  # 公开的服务器状态，首页组件（T2）每 30 秒读一次。
  class StatusController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def show
      render json: ServerStatus.current
    end
  end
end
