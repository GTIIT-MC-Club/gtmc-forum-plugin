# frozen_string_literal: true

module DiscourseGtmc
  # GET /gtmc/skins/:texture_hash.png：转发皮肤站的贴图。皮肤站的贴图没有 CORS 头，
  # 浏览器不让 WebGL 读别的域名的图，所以由论坛同源转发。
  # 网址就是内容的哈希，内容不会变，浏览器可以永久缓存。
  class SkinsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    CACHE_TTL = 1.day
    MAX_FETCHES_PER_MINUTE = 30

    # 浏览器直接请求图片，同 IconsController
    skip_before_action :check_xhr,
                       :preload_json,
                       :redirect_to_login_if_required,
                       :redirect_to_profile_if_required

    def show
      # 面板只给登录用户看；不让游客借论坛去刷皮肤站
      raise Discourse::NotFound if current_user.nil?
      png = cached_texture(params[:texture_hash])
      raise Discourse::NotFound if png.nil?

      immutable_for 1.year
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_data png, type: "image/png", disposition: "inline"
    end

    private

    def cached_texture(texture_hash)
      cache_key = "gtmc_skin_texture:#{texture_hash}"
      cached = Discourse.cache.read(cache_key)
      return cached if cached

      RateLimiter.new(
        current_user,
        "gtmc_skin_texture",
        MAX_FETCHES_PER_MINUTE,
        1.minute,
      ).performed!
      png = SkinSite.texture(texture_hash)
      Discourse.cache.write(cache_key, png, expires_in: CACHE_TTL) if png
      png
    end
  end
end
