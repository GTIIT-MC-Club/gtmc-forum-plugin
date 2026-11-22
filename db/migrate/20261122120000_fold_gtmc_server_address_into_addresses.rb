# frozen_string_literal: true

# gtmc_servers 去掉了旧的单个 address 字段，地址都放在 addresses 列表里。
# 旧值不在列表里的话补进去：列表原来是空的就不加标签，否则按 IP 标「内网」或「外网」。
class FoldGtmcServerAddressIntoAddresses < ActiveRecord::Migration[8.0]
  PRIVATE_HOST = /\A(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|localhost\b)/

  def up
    raw = DB.query_single("SELECT value FROM site_settings WHERE name = 'gtmc_servers'").first
    return if raw.blank?

    servers = JSON.parse(raw)
    return if !servers.is_a?(Array)

    servers.each do |server|
      next if !server.is_a?(Hash) || !server.key?("address")
      address = server.delete("address").to_s.strip
      next if address.empty?

      addresses = Array(server["addresses"]).select { |item| item.is_a?(Hash) }
      next if addresses.any? { |item| item["address"].to_s.strip == address }

      label =
        if addresses.empty?
          nil
        else
          PRIVATE_HOST.match?(address) ? "内网" : "外网"
        end
      server["addresses"] = addresses + [{ "label" => label, "address" => address }.compact]
    end

    DB.exec(
      "UPDATE site_settings SET value = :value, updated_at = NOW() WHERE name = 'gtmc_servers'",
      value: servers.to_json,
    )
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
