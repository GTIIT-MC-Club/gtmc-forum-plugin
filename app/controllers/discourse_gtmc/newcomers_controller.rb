# frozen_string_literal: true

module DiscourseGtmc
  # 右栏「新人进服」面板和手机进度卡用的数据，见 NewcomerProgress。
  class NewcomersController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def show
      render json: NewcomerProgress.for(current_user)
    end
  end
end
