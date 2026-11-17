# frozen_string_literal: true

RSpec.describe DiscourseGtmc::StatusController do
  let(:survival_server) do
    {
      server_id: "survival",
      name: "生存服",
      address: "survival.gtmc.test",
      map_url: "https://map.gtmc.test/survival",
      icon: "gtmc-bricks",
      color: "#5DBB47",
    }
  end
  let(:creative_server) do
    {
      server_id: "creative",
      name: "创造服",
      address: "creative.gtmc.test",
      map_url: "",
      icon: "gtmc-hammer",
      color: "",
    }
  end
  let(:modded_server) do
    { server_id: "modded", name: "模组服", address: "modded.gtmc.test", icon: "gtmc-gear" }
  end

  let(:offline_fields) do
    {
      "online" => false,
      "version" => nil,
      "players_online" => nil,
      "players_max" => nil,
      "players" => nil,
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

  def post_heartbeat(server_id:, players_online: 2, player_names: nil)
    post "/gtmc/server/heartbeat.json",
         params: {
           server_id: server_id,
           version: "1.21.4-232-ver/1.21.4",
           players_online: players_online,
           players_max: 20,
           player_names: player_names || Array.new(players_online) { |index| "Player#{index}" },
           tps: 19.98,
         },
         headers: {
           "Api-Key" => server_api_key.key,
           "Api-Username" => "system",
         },
         as: :json
    expect(response.parsed_body).to eq("status" => "ok")
  end

  # schema 在保存时已经挡掉了缺 icon、color 太长的值；这里模拟 schema 出现之前存下的旧数据
  # （或绕过校验直接写库的数据），检验读取时的第二道防线。
  def store_servers_bypassing_schema(*servers)
    allow(SiteSetting).to receive(:gtmc_servers).and_return(servers.to_json)
  end

  def statuses_by_server_id
    get "/gtmc/status.json"
    expect(response.status).to eq(200)
    response.parsed_body["servers"].index_by { |server| server["server_id"] }
  end

  fab!(:user)

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
    expect(response.parsed_body).to eq("refresh_interval_seconds" => 30, "servers" => [])
  end

  it "returns an empty server list when gtmc_servers is emptied" do
    SiteSetting.gtmc_servers = "[]"

    get "/gtmc/status.json"

    expect(response.parsed_body).to eq("refresh_interval_seconds" => 30, "servers" => [])
  end

  it "lists every registered server as offline with its display fields before any heartbeat" do
    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "refresh_interval_seconds" => 30,
      "servers" => [
        {
          "server_id" => "survival",
          "name" => "生存服",
          "address" => "survival.gtmc.test",
          "map_url" => "https://map.gtmc.test/survival",
          "icon" => "gtmc-bricks",
          "color" => "#5dbb47",
          **offline_fields,
        },
        {
          "server_id" => "creative",
          "name" => "创造服",
          "address" => "creative.gtmc.test",
          "map_url" => nil,
          "icon" => "gtmc-hammer",
          "color" => nil,
          **offline_fields,
        },
      ],
    )
  end

  it "keeps the order of gtmc_servers while no server is online" do
    register_servers(creative_server, survival_server)

    get "/gtmc/status.json"

    expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
      %w[creative survival],
    )
  end

  it "reports a server online with its reported numbers right after its heartbeat" do
    freeze_time
    sign_in(user)
    post_heartbeat(server_id: "survival")

    status = statuses_by_server_id["survival"]

    expect(status).to include(
      "server_id" => "survival",
      "name" => "生存服",
      "address" => "survival.gtmc.test",
      "map_url" => "https://map.gtmc.test/survival",
      "icon" => "gtmc-bricks",
      "color" => "#5dbb47",
      "online" => true,
      "version" => "1.21.4-232-ver/1.21.4",
      "players_online" => 2,
      "players_max" => 20,
      "tps" => 19.98,
      "updated_at" => Time.zone.now.iso8601(3),
    )
    expect(status["players"].map { |player| player["mc_name"] }).to eq(%w[Player0 Player1])
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

  describe "ordering" do
    before { register_servers(survival_server, creative_server, modded_server) }

    it "lists online servers first, the most crowded one first, and offline servers last" do
      post_heartbeat(server_id: "modded", players_online: 1)
      post_heartbeat(server_id: "creative", players_online: 5)

      get "/gtmc/status.json"

      expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
        %w[creative modded survival],
      )
    end

    it "keeps the gtmc_servers order between online servers with the same player count" do
      post_heartbeat(server_id: "modded", players_online: 3)
      post_heartbeat(server_id: "creative", players_online: 3)
      post_heartbeat(server_id: "survival", players_online: 3)

      get "/gtmc/status.json"

      expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
        %w[survival creative modded],
      )
    end

    it "keeps the gtmc_servers order between offline servers" do
      post_heartbeat(server_id: "creative", players_online: 0)

      get "/gtmc/status.json"

      expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
        %w[creative survival modded],
      )
    end

    it "moves a server behind the others when its heartbeat times out" do
      freeze_time
      post_heartbeat(server_id: "survival", players_online: 9)
      freeze_time 60.seconds.from_now
      post_heartbeat(server_id: "creative", players_online: 1)
      freeze_time 31.seconds.from_now

      get "/gtmc/status.json"

      expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
        %w[creative survival modded],
      )
    end
  end

  describe "players" do
    before do
      register_servers(survival_server, creative_server, modded_server)
      post_heartbeat(server_id: "survival", player_names: %w[Steve Alex])
      post_heartbeat(server_id: "creative", players_online: 0, player_names: [])
    end

    it "returns null players to anonymous visitors but keeps the counts" do
      statuses = statuses_by_server_id

      expect(statuses["survival"]).to include("players_online" => 2, "players" => nil)
      expect(statuses["creative"]).to include("players_online" => 0, "players" => nil)
    end

    it "does not leak the reported names to anonymous visitors anywhere in the response" do
      get "/gtmc/status.json"

      expect(response.body).not_to include("Steve")
      expect(response.body).not_to include("player_names")
    end

    it "lists each player with an avatar template to logged-in users" do
      sign_in(user)

      players = statuses_by_server_id["survival"]["players"]

      expect(players.map { |player| player["mc_name"] }).to eq(%w[Steve Alex])
      expect(players.first["avatar_template"]).to eq(User.system_avatar_template("Steve"))
      expect(players.first["avatar_template"]).to include("{size}")
    end

    it "returns an empty list for a logged-in user when nobody is online" do
      sign_in(user)

      expect(statuses_by_server_id["creative"]["players"]).to eq([])
    end

    it "returns null players for an offline server even to logged-in users" do
      sign_in(user)

      expect(statuses_by_server_id["modded"]).to include(offline_fields)
    end
  end

  describe "server fields" do
    it "lowercases the color so clients see one spelling" do
      expect(statuses_by_server_id["survival"]["color"]).to eq("#5dbb47")
    end

    it "returns a null color when it is left empty" do
      expect(statuses_by_server_id["creative"]["color"]).to be_nil
    end

    it "refuses to save an entry without an icon" do
      expect { register_servers(creative_server.except(:icon)) }.to raise_error(
        Discourse::InvalidParameters,
        /icon/,
      )
    end

    it "ignores a stored entry without an icon" do
      store_servers_bypassing_schema(survival_server, creative_server.except(:icon))

      expect(statuses_by_server_id.keys).to eq(["survival"])
    end

    it "ignores an entry whose icon is not a plain icon name" do
      store_servers_bypassing_schema(
        survival_server,
        creative_server.merge(icon: 'x" onload="alert(1)'),
      )

      expect(statuses_by_server_id.keys).to eq(["survival"])
    end

    it "ignores an entry whose color is not #RRGGBB" do
      %w[red #fff #5DBB4 #5DBB47;x rgb(0,0,0) url(x) #GGGGGG].each do |color|
        store_servers_bypassing_schema(survival_server, creative_server.merge(color: color))

        expect(statuses_by_server_id.keys).to eq(["survival"])
      end
    end

    it "does not let an entry rejected for its icon block a later entry with the same server_id" do
      store_servers_bypassing_schema(
        survival_server.merge(icon: ""),
        survival_server.merge(name: "第二个生存服"),
      )

      expect(statuses_by_server_id["survival"]["name"]).to eq("第二个生存服")
    end
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

  it "tells the administrator why an entry is ignored when gtmc_servers is saved" do
    fake_logger = track_log_messages { register_servers(creative_server.merge(color: "red")) }

    expect(fake_logger.warnings.grep(/color must be empty or look like #RRGGBB/).size).to eq(1)
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
