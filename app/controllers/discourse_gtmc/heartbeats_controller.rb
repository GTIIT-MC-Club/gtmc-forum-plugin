# frozen_string_literal: true

module DiscourseGtmc
  # MC 插件定时上报的心跳，契约见 PLAN.md 4.1。
  #
  # 只接受管理员的 API Key（MC 插件用 Api-Username: system）。带作用域的 Key 必须勾了
  # gtmc:server，否则 Discourse 在进入本控制器之前就以 403 拒绝；不限作用域的全局 Key 也能用。
  #
  # 请求体必须是 JSON（Content-Type: application/json），数值字段必须是 JSON 数字：
  # 表单编码会把数字变成字符串，这里按类型严格校验，会返回 400。
  class HeartbeatsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    # 远超社团服的规模，只用来挡住异常请求把 Redis 里的心跳撑得过大
    MAX_PLAYER_NAMES = 1000
    # Paper 的版本串形如 "1.21.4-232-ver/1.21.4@abcdef0 (MC: 1.21.4)"，200 字符足够宽裕
    MAX_VERSION_LENGTH = 200
    # Minecraft 玩家名的长度上限
    MAX_MC_NAME_LENGTH = 16

    before_action :ensure_server_api_request

    def create
      ServerStatus.record_heartbeat(
        version: version_param,
        players_online: non_negative_integer_param(:players_online),
        players_max: non_negative_integer_param(:players_max),
        player_names: player_names_param,
        tps: tps_param,
      )
      render json: { status: "ok" }
    end

    private

    # 浏览器里登录的管理员、或没带 Key 的请求都不能伪造心跳。
    # is_api? 为真时 current_user 一定存在：Key 找不到用户时 Discourse 已经抛出 403。
    def ensure_server_api_request
      raise Discourse::InvalidAccess if !is_api? || !current_user.admin?
    end

    def version_param
      version = params[:version]
      if !version.is_a?(String) || version.blank? || version.length > MAX_VERSION_LENGTH
        raise Discourse::InvalidParameters.new(:version)
      end
      version
    end

    def non_negative_integer_param(name)
      value = params[name]
      raise Discourse::InvalidParameters.new(name) if !value.is_a?(Integer) || value.negative?
      value
    end

    def player_names_param
      player_names = params[:player_names]
      valid =
        player_names.is_a?(Array) && player_names.size <= MAX_PLAYER_NAMES &&
          player_names.all? do |mc_name|
            mc_name.is_a?(String) && mc_name.present? && mc_name.length <= MAX_MC_NAME_LENGTH
          end
      raise Discourse::InvalidParameters.new(:player_names) if !valid
      player_names
    end

    def tps_param
      tps = params[:tps]
      raise Discourse::InvalidParameters.new(:tps) if !tps.is_a?(Numeric) || tps.negative?
      tps
    end
  end
end
