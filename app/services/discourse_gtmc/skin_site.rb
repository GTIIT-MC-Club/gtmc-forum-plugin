# frozen_string_literal: true

module DiscourseGtmc
  # 问皮肤站一个人建了哪些角色。皮肤站一侧是 gtmc-auth-core 里 gtmc-casdoor 插件的
  # POST /api/gtmc/players，论坛和皮肤站的账号都来自 GTMC 账号，按学校邮箱对得上。
  class SkinSite
    TIMEOUT_SECONDS = 5

    # 返回角色名数组（没有账号或没建角色时是空数组）；没配置、连不上、返回不对时返回 nil。
    def self.player_names(email)
      url = SiteSetting.gtmc_skin_api_url.strip
      key = SiteSetting.gtmc_skin_api_key.strip
      return nil if url.blank? || key.blank? || email.blank?

      uri = URI.parse(url)
      return nil if !uri.is_a?(URI::HTTP) || uri.host.blank?

      request = Net::HTTP::Post.new(uri)
      request["X-Gtmc-Key"] = key
      request["Accept"] = "application/json"
      request.set_form_data("email" => email)

      response =
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT_SECONDS,
          read_timeout: TIMEOUT_SECONDS,
        ) { |http| http.request(request) }

      if !response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[discourse-gtmc] 皮肤站角色接口返回 #{response.code}")
        return nil
      end

      players = JSON.parse(response.body)["players"]
      valid = players.is_a?(Array) && players.all? { |name| name.is_a?(String) }
      valid ? players : nil
    rescue StandardError => e
      Rails.logger.warn("[discourse-gtmc] 皮肤站角色接口请求失败：#{e.class}: #{e.message}")
      nil
    end
  end
end
