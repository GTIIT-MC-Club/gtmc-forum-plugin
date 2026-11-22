# frozen_string_literal: true

module DiscourseGtmc
  # GET /gtmc/servers/:server_id/icon.png：缓存的服务器图标，status.json 的 favicon_url 指向这里。
  # 网址里带内容哈希（?v=），所以可以让浏览器永久缓存。
  class IconsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    # 浏览器直接请求图片，不是 XHR，也不该跳去登录页；跳过的列表照抄核心的 UserAvatarsController
    skip_before_action :check_xhr,
                       :preload_json,
                       :redirect_to_login_if_required,
                       :redirect_to_profile_if_required

    def show
      server_id = params[:server_id]
      raise Discourse::NotFound if !ServerRegistry.registered_server_id?(server_id)
      png = ServerFavicon.png(server_id)
      raise Discourse::NotFound if png.nil?

      immutable_for 1.year
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_data png, type: "image/png", disposition: "inline"
    end
  end
end
