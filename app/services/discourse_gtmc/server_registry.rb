# frozen_string_literal: true

module DiscourseGtmc
  # 站点设置 gtmc_servers 里登记的 MC 服，契约见 PLAN.md 4.1。
  #
  # 设置的 schema 管不了 server_id、icon、color 的格式，也管不了 server_id 的唯一性，所以读取时过滤：
  # 不合格的项、重复 server_id 的后几项都当作没登记。读取发生在每次 status.json 请求里，不在这里记日志；
  # 管理员保存设置时由 plugin.rb 调 log_ignored_entries 记一次。
  class ServerRegistry
    # \A \z 而不是 ^ $：Ruby 的 ^ $ 按行匹配，"survival\nx" 也能通过
    SERVER_ID_PATTERN = /\A[a-z0-9-]{1,32}\z/

    # 图标选择器给出的名字：Font Awesome 的 "cube"、"far-clock"，主题的 "gtmc-bricks"。
    # 64 只用来挡住误粘贴的长文本；字符集排除了引号和空格，名字之后会进 HTML 属性。
    ICON_PATTERN = /\A[a-z0-9_-]{1,64}\z/

    # 颜色会写进前端元素的 style 属性，所以只认 #RRGGBB，不放行 CSS 的其他写法。
    COLOR_PATTERN = /\A#[0-9a-fA-F]{6}\z/

    Server = Data.define(:server_id, :name, :address, :map_url, :icon, :color)

    # 按设置里的顺序返回。
    def self.servers
      accepted_entries, _ignored_entries = partition_entries
      accepted_entries.map do |entry|
        Server.new(
          server_id: entry["server_id"],
          name: entry["name"],
          address: entry["address"],
          map_url: entry["map_url"].presence,
          icon: entry["icon"],
          # 统一成小写，前端和测试只需面对一种写法
          color: entry["color"].presence&.downcase,
        )
      end
    end

    def self.registered_server_id?(server_id)
      servers.any? { |server| server.server_id == server_id }
    end

    def self.log_ignored_entries
      _accepted_entries, ignored_entries = partition_entries
      ignored_entries.each do |entry, reason|
        Rails.logger.warn(
          "[discourse-gtmc] Ignoring gtmc_servers entry with server_id #{entry["server_id"].inspect}: " \
            "#{reason}. Heartbeats for it will get unknown_server until the setting is fixed.",
        )
      end
    end

    # 返回 [认的项, [[忽略的项, 原因], ...]]，两者都保持设置里的顺序。
    def self.partition_entries
      seen_server_ids = Set.new
      accepted_entries = []
      ignored_entries = []
      registered_entries.each do |entry|
        reason = rejection_reason(entry, seen_server_ids)
        reason ? ignored_entries << [entry, reason] : accepted_entries << entry
      end
      [accepted_entries, ignored_entries]
    end
    private_class_method :partition_entries

    # 检查顺序有意义：先看格式再看重复，这样一项因为 icon 不合格被忽略时，不会占掉它的 server_id，
    # 让后面同 server_id 的合格项也被当成重复。
    def self.rejection_reason(entry, seen_server_ids)
      server_id = entry["server_id"]
      icon = entry["icon"]
      color = entry["color"]

      if !server_id.is_a?(String) || !SERVER_ID_PATTERN.match?(server_id)
        "server_id must match #{SERVER_ID_PATTERN.inspect}"
      elsif !icon.is_a?(String) || !ICON_PATTERN.match?(icon)
        "icon must be set and match #{ICON_PATTERN.inspect}"
      elsif color.present? && (!color.is_a?(String) || !COLOR_PATTERN.match?(color))
        "color must be empty or look like #RRGGBB"
      elsif !seen_server_ids.add?(server_id)
        "server_id is already used by an earlier entry"
      end
    end
    private_class_method :rejection_reason

    # 设置未改过时取到的是 YAML 里的默认值 []，改过之后是 JSON 字符串；
    # 写法照抄核心自带插件 discourse-oauth2-basic 读 objects 设置的方式，两种情况都能处理。
    def self.registered_entries
      JSON.parse(SiteSetting.gtmc_servers.presence || "[]")
    end
    private_class_method :registered_entries
  end
end
