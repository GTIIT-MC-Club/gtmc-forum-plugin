# frozen_string_literal: true

RSpec.describe DiscourseGtmc::StatusController do
  let(:survival_server) do
    {
      server_id: "survival",
      name: "生存服",
      address: "survival.gtmc.test",
      map_url: "https://map.gtmc.test/survival",
    }
  end
  let(:creative_server) do
    { server_id: "creative", name: "创造服", address: "creative.gtmc.test", map_url: "" }
  end

  let(:offline_fields) do
    {
      "online" => false,
      "version" => nil,
      "players_online" => nil,
      "players_max" => nil,
      "player_names" => nil,
      "tps" => nil,
      "updated_at" => nil,
    }
  end

  let(:server_api_key) do
    Fabricate(
      :api_key,
      user: Discourse.system_user,
      api_key_scopes: [Fabricate.build(:api_key_scope, resource: "gtmc", action: "server")],
    )
  end

  def register_servers(*servers)
    SiteSetting.gtmc_servers = servers.to_json
  end

  def post_heartbeat(server_id:, players_online: 2)
    post "/gtmc/server/heartbeat.json",
         params: {
           server_id: server_id,
           version: "1.21.4-232-ver/1.21.4",
           players_online: players_online,
           players_max: 20,
           player_names: Array.new(players_online) { |index| "Player#{index}" },
           tps: 19.98,
         },
         headers: {
           "Api-Key" => server_api_key.key,
           "Api-Username" => "system",
         },
         as: :json
    expect(response.parsed_body).to eq("status" => "ok")
  end

  def statuses_by_server_id
    get "/gtmc/status.json"
    expect(response.status).to eq(200)
    response.parsed_body["servers"].index_by { |server| server["server_id"] }
  end

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_heartbeat_timeout_seconds = 90
    register_servers(survival_server, creative_server)
  end

  it "returns an empty server list when gtmc_servers has never been set" do
    # 回到 settings.yml 里的默认值：此时 SiteSetting 返回的是数组 [] 而不是 JSON 字符串
    SiteSetting.remove_override!(:gtmc_servers)

    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq("servers" => [])
  end

  it "returns an empty server list when gtmc_servers is emptied" do
    SiteSetting.gtmc_servers = "[]"

    get "/gtmc/status.json"

    expect(response.parsed_body).to eq("servers" => [])
  end

  it "lists every registered server as offline with its display fields before any heartbeat" do
    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "servers" => [
        {
          "server_id" => "survival",
          "name" => "生存服",
          "address" => "survival.gtmc.test",
          "map_url" => "https://map.gtmc.test/survival",
          **offline_fields,
        },
        {
          "server_id" => "creative",
          "name" => "创造服",
          "address" => "creative.gtmc.test",
          "map_url" => nil,
          **offline_fields,
        },
      ],
    )
  end

  it "keeps the order of gtmc_servers" do
    register_servers(creative_server, survival_server)

    get "/gtmc/status.json"

    expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
      %w[creative survival],
    )
  end

  it "reports a server online with its reported numbers right after its heartbeat" do
    freeze_time
    post_heartbeat(server_id: "survival")

    expect(statuses_by_server_id["survival"]).to eq(
      "server_id" => "survival",
      "name" => "生存服",
      "address" => "survival.gtmc.test",
      "map_url" => "https://map.gtmc.test/survival",
      "online" => true,
      "version" => "1.21.4-232-ver/1.21.4",
      "players_online" => 2,
      "players_max" => 20,
      "player_names" => %w[Player0 Player1],
      "tps" => 19.98,
      "updated_at" => Time.zone.now.iso8601(3),
    )
  end

  it "keeps heartbeats of different servers apart" do
    post_heartbeat(server_id: "survival", players_online: 2)
    post_heartbeat(server_id: "creative", players_online: 5)

    statuses = statuses_by_server_id
    expect(statuses["survival"]["players_online"]).to eq(2)
    expect(statuses["creative"]["players_online"]).to eq(5)
  end

  it "leaves a server offline when only another server sends heartbeats" do
    post_heartbeat(server_id: "survival")

    statuses = statuses_by_server_id
    expect(statuses["survival"]["online"]).to eq(true)
    expect(statuses["creative"]).to include(offline_fields)
  end

  it "reports one server offline after its timeout while the other stays online" do
    freeze_time
    post_heartbeat(server_id: "survival")
    freeze_time 60.seconds.from_now
    post_heartbeat(server_id: "creative")

    freeze_time 31.seconds.from_now
    statuses = statuses_by_server_id

    expect(statuses["survival"]).to include(offline_fields)
    expect(statuses["creative"]["online"]).to eq(true)
  end

  it "is readable by anonymous visitors" do
    post_heartbeat(server_id: "survival")

    expect(statuses_by_server_id["survival"]["online"]).to eq(true)
  end

  it "stays online while the last heartbeat is younger than the timeout" do
    freeze_time
    post_heartbeat(server_id: "survival")

    freeze_time 89.seconds.from_now

    expect(statuses_by_server_id["survival"]["online"]).to eq(true)
  end

  it "reports offline once no heartbeat has arrived for longer than the timeout" do
    freeze_time
    post_heartbeat(server_id: "survival")

    freeze_time 91.seconds.from_now

    expect(statuses_by_server_id["survival"]).to include(offline_fields)
  end

  it "applies a changed timeout to a heartbeat that was already stored" do
    freeze_time
    post_heartbeat(server_id: "survival")

    freeze_time 60.seconds.from_now
    SiteSetting.gtmc_heartbeat_timeout_seconds = 30

    expect(statuses_by_server_id["survival"]["online"]).to eq(false)
  end

  it "stops listing a server once it is removed from gtmc_servers, even with its heartbeat still stored" do
    post_heartbeat(server_id: "creative")

    register_servers(survival_server)

    expect(statuses_by_server_id.keys).to eq(["survival"])
  end

  it "ignores entries whose server_id breaks the format" do
    register_servers(survival_server, creative_server.merge(server_id: "Creative Server"))

    expect(statuses_by_server_id.keys).to eq(["survival"])
  end

  it "keeps only the first of several entries with the same server_id" do
    register_servers(survival_server, survival_server.merge(name: "重复的生存服"))

    get "/gtmc/status.json"

    expect(response.parsed_body["servers"].map { |server| server["name"] }).to eq(["生存服"])
  end

  it "logs one warning per ignored entry when gtmc_servers is saved, and none when status is read" do
    fake_logger =
      track_log_messages do
        register_servers(
          survival_server,
          survival_server.merge(name: "重复的生存服"),
          creative_server.merge(server_id: "Creative"),
        )
      end
    expect(fake_logger.warnings.grep(/gtmc_servers/).size).to eq(2)

    fake_logger = track_log_messages { get "/gtmc/status.json" }
    expect(fake_logger.warnings.grep(/gtmc_servers/)).to be_empty
  end

  it "returns 404 when gtmc_enabled is off" do
    SiteSetting.gtmc_enabled = false

    get "/gtmc/status.json"

    expect(response.status).to eq(404)
  end
end
