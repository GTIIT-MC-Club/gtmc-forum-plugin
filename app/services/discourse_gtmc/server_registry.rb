# frozen_string_literal: true

module DiscourseGtmc
  # 站点设置 gtmc_servers 里登记的 MC 服，契约见 PLAN.md 4.1。
  #
  # 设置的 schema 管不了 server_id 的格式和唯一性，所以读取时过滤：格式不对的项、重复 server_id
  # 的后几项都当作没登记。读取发生在每次 status.json 请求里，不在这里记日志；
  # 管理员保存设置时由 plugin.rb 调 log_ignored_entries 记一次。
  class ServerRegistry
    # \A \z 而不是 ^ $：Ruby 的 ^ $ 按行匹配，"survival\nx" 也能通过
    SERVER_ID_PATTERN = /\A[a-z0-9-]{1,32}\z/

    Server = Data.define(:server_id, :name, :address, :map_url)

    # 按设置里的顺序返回。
    def self.servers
      accepted_entries, _ignored_entries = partition_entries
      accepted_entries.map do |entry|
        Server.new(
          server_id: entry["server_id"],
          name: entry["name"],
          address: entry["address"],
          map_url: entry["map_url"].presence,
        )
      end
    end

    def self.registered_server_id?(server_id)
      servers.any? { |server| server.server_id == server_id }
    end

    def self.log_ignored_entries
      _accepted_entries, ignored_entries = partition_entries
      ignored_entries.each do |entry|
        Rails.logger.warn(
          "[discourse-gtmc] Ignoring gtmc_servers entry with server_id #{entry["server_id"].inspect}: " \
            "it must match #{SERVER_ID_PATTERN.inspect} and be unique. " \
            "Heartbeats for it will get unknown_server until the setting is fixed.",
        )
      end
    end

    # 返回 [认的项, 忽略的项]，两者都保持设置里的顺序。
    def self.partition_entries
      seen_server_ids = Set.new
      registered_entries.partition do |entry|
        server_id = entry["server_id"]
        server_id.is_a?(String) && SERVER_ID_PATTERN.match?(server_id) &&
          seen_server_ids.add?(server_id).present?
      end
    end
    private_class_method :partition_entries

    # 设置未改过时取到的是 YAML 里的默认值 []，改过之后是 JSON 字符串；
    # 写法照抄核心自带插件 discourse-oauth2-basic 读 objects 设置的方式，两种情况都能处理。
    def self.registered_entries
      JSON.parse(SiteSetting.gtmc_servers.presence || "[]")
    end
    private_class_method :registered_entries
  end
end
