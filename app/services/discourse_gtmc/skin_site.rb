# frozen_string_literal: true

module DiscourseGtmc
  # 问皮肤站一个人建了哪些角色。皮肤站一侧是 gtmc-auth-core 里 gtmc-casdoor 插件的
  # POST /api/gtmc/players，论坛和皮肤站的账号都来自 GTMC 账号，按学校邮箱对得上。
  class SkinSite
    # 请求占着网页 worker（生产只有 3 个），所以等得很短
    TIMEOUT_SECONDS = 2
    # 连不上或超时后，全站这么久不再问皮肤站，直接当作问不到，免得每个访客都来等一次超时
    DOWN_SECONDS = 30
    DOWN_CACHE_KEY = "gtmc_skin_site_down"

    class Unavailable < StandardError
    end

    TEXTURE_HASH = /\A[0-9a-f]{64}\z/
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    # 普通皮肤只有几 KB，高清皮肤几百 KB；贴图要进 Redis，所以设上限
    MAX_TEXTURE_BYTES = 1.megabyte

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

      response = perform(uri, request)
      if !response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[discourse-gtmc] 皮肤站角色接口返回 #{response.code}")
        return nil
      end

      players = JSON.parse(response.body)["players"]
      valid = players.is_a?(Array) && players.all? { |name| name.is_a?(String) }
      valid ? players : nil
    rescue Unavailable
      nil
    rescue StandardError => e
      Rails.logger.warn("[discourse-gtmc] 皮肤站角色接口请求失败：#{e.class}: #{e.message}")
      nil
    end

    # 一个角色用的皮肤：{ hash:, slim: }，没设皮肤时是空 Hash；连不上、返回不对时返回 nil。
    # 皮肤站自带的 /csl/<角色名>.json，公开接口，不用密钥。slim 是细手臂（Alex）模型。
    def self.skin(name)
      response = get("/csl/#{ERB::Util.url_encode(name)}.json")
      return nil if response.nil?
      return {} if response.is_a?(Net::HTTPNotFound)
      return nil if !response.is_a?(Net::HTTPSuccess)

      skins = JSON.parse(response.body)["skins"]
      # 没有皮肤时 PHP 会把空数组编码成 []
      return {} if !skins.is_a?(Hash)
      slim = skins["slim"].present?
      hash = slim ? skins["slim"] : skins["default"]
      hash.to_s.match?(TEXTURE_HASH) ? { hash: hash, slim: slim } : {}
    rescue JSON::ParserError
      nil
    end

    # 贴图的 PNG 内容，取不到时返回 nil
    def self.texture(hash)
      return nil if !hash.match?(TEXTURE_HASH)
      response = get("/textures/#{hash}")
      return nil if !response.is_a?(Net::HTTPSuccess)
      png = response.body.b
      png if png.start_with?(PNG_SIGNATURE) && png.bytesize <= MAX_TEXTURE_BYTES
    end

    def self.get(path)
      base = SiteSetting.gtmc_skin_site_url.strip.chomp("/")
      return nil if base.blank?
      uri = URI.parse("#{base}#{path}")
      return nil if !uri.is_a?(URI::HTTP) || uri.host.blank?
      perform(uri, Net::HTTP::Get.new(uri))
    rescue Unavailable
      nil
    rescue StandardError => e
      Rails.logger.warn("[discourse-gtmc] 皮肤站请求失败：#{e.class}: #{e.message}")
      nil
    end
    private_class_method :get

    def self.perform(uri, request)
      raise Unavailable if Discourse.cache.read(DOWN_CACHE_KEY)

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS,
        read_timeout: TIMEOUT_SECONDS,
        # 默认会把超时的 GET 自动重试一次，等待时间翻倍
        max_retries: 0,
      ) { |http| http.request(request) }
    rescue Timeout::Error, SystemCallError, SocketError, EOFError, OpenSSL::SSL::SSLError
      Discourse.cache.write(DOWN_CACHE_KEY, true, expires_in: DOWN_SECONDS.seconds)
      raise
    end
    private_class_method :perform
  end
end
