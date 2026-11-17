# frozen_string_literal: true

module DiscourseGtmc
  # 右栏「新人进服」面板的第二步（读新人指南）用的数据，契约见 PLAN.md 4.1。
  class NewcomerGuidesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def show
      topic = NewcomerGuide.topic_visible_to(current_user)
      render json: {
               topic_url: topic&.relative_url,
               read: NewcomerGuide.read_by?(current_user, topic),
             }
    end
  end
end
