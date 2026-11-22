# frozen_string_literal: true

module DiscourseGtmc
  # 各服的图标（server-icon.png），由 ServerPoller 用 Server List Ping 取来，存在 Redis 里不设过期：
  # 服离线时照样显示上次取到的图标。Redis 清空的后果只是服下次在线之前用 gtmc_servers 里选的 icon。
  #
  # 图标很少变，所以只在缓存超过 REFRESH_INTERVAL 时重取。服务器去掉了图标时也记一笔（png 为 nil），
  # 免得每 30 秒连一次。
  class ServerFavicon
    REDIS_KEY_PREFIX = "gtmc_server_favicon"
    REFRESH_INTERVAL = 1.hour

    def self.stale?(server_id)
      cached = read(server_id)
      cached.nil? || Time.zone.parse(cached[:fetched_at]) < REFRESH_INTERVAL.ago
    end

    def self.store(server_id, png)
      entry = { png: png && Base64.strict_encode64(png), fetched_at: Time.zone.now.iso8601(3) }
      Discourse.redis.set(redis_key(server_id), entry.to_json)
    end

    def self.png(server_id)
      encoded = read(server_id)&.dig(:png)
      encoded && Base64.strict_decode64(encoded)
    end

    # 带上内容的短哈希：图标变了网址就变，浏览器可以一直缓存同一个网址
    def self.url(server_id)
      encoded = read(server_id)&.dig(:png)
      return if encoded.nil?
      version = Digest::SHA1.hexdigest(encoded)[0, 12]
      "/gtmc/servers/#{server_id}/icon.png?v=#{version}"
    end

    def self.read(server_id)
      raw = Discourse.redis.get(redis_key(server_id))
      raw && JSON.parse(raw, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
    private_class_method :read

    def self.redis_key(server_id)
      "#{REDIS_KEY_PREFIX}:#{server_id}"
    end
    private_class_method :redis_key
  end
end
