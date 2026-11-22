# frozen_string_literal: true

require_relative "../../db/migrate/20261122120000_fold_gtmc_server_address_into_addresses"

RSpec.describe FoldGtmcServerAddressIntoAddresses do
  def stored_servers
    JSON.parse(DB.query_single("SELECT value FROM site_settings WHERE name = 'gtmc_servers'").first)
  end

  before do
    old_servers = [
      { "server_id" => "a", "address" => "frp-pen.com:54881", "icon" => "cube" },
      {
        "server_id" => "b",
        "address" => "10.202.28.100:25560",
        "addresses" => [{ "label" => "外网", "address" => "frp-leg.com:1" }],
        "icon" => "cube",
      },
      {
        "server_id" => "c",
        "address" => "frp-leg.com:2",
        "addresses" => [{ "address" => "frp-leg.com:2" }],
        "icon" => "cube",
      },
    ]
    DB.exec("DELETE FROM site_settings WHERE name = 'gtmc_servers'")
    DB.exec(<<~SQL, value: old_servers.to_json)
      INSERT INTO site_settings (name, data_type, value, created_at, updated_at)
      VALUES ('gtmc_servers', #{SiteSettings::TypeSupervisor.types[:objects]}, :value, NOW(), NOW())
    SQL
  end

  it "moves the old address into the addresses list" do
    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(stored_servers).to eq(
      [
        {
          "server_id" => "a",
          "icon" => "cube",
          "addresses" => [{ "address" => "frp-pen.com:54881" }],
        },
        {
          "server_id" => "b",
          "icon" => "cube",
          "addresses" => [
            { "label" => "外网", "address" => "frp-leg.com:1" },
            { "label" => "内网", "address" => "10.202.28.100:25560" },
          ],
        },
        { "server_id" => "c", "icon" => "cube", "addresses" => [{ "address" => "frp-leg.com:2" }] },
      ],
    )
  end
end
