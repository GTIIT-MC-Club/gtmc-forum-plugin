# frozen_string_literal: true

RSpec.describe DiscourseGtmc::HeartbeatsController do
  fab!(:admin)
  fab!(:user)

  let(:heartbeat_body) do
    {
      server_id: "survival",
      version: "1.21.4-232-ver/1.21.4",
      players_online: 2,
      players_max: 20,
      player_names: %w[Steve Alex],
      tps: 19.98,
    }
  end

  def gtmc_server_api_key(owner: Discourse.system_user)
    Fabricate(
      :api_key,
      user: owner,
      api_key_scopes: [Fabricate.build(:api_key_scope, resource: "gtmc", action: "server")],
    )
  end

  def post_heartbeat(body: heartbeat_body, api_key: gtmc_server_api_key, username: "system")
    headers = api_key ? { "Api-Key" => api_key.key, "Api-Username" => username } : {}
    post "/gtmc/server/heartbeat.json", params: body, headers: headers, as: :json
  end

  def status_of(server_id)
    get "/gtmc/status.json"
    response.parsed_body["servers"].find { |server| server["server_id"] == server_id }
  end

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_servers = [
      { server_id: "survival", name: "生存服", address: "survival.gtmc.test" },
    ].to_json
  end

  it "accepts a heartbeat from a gtmc:server key and answers with status ok" do
    post_heartbeat

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq("status" => "ok")
  end

  it "accepts a heartbeat from an empty server" do
    post_heartbeat(body: heartbeat_body.merge(players_online: 0, player_names: []))

    expect(response.status).to eq(200)
    expect(status_of("survival")).to include(
      "online" => true,
      "players_online" => 0,
      "player_names" => [],
    )
  end

  it "accepts a heartbeat from a global key without scopes" do
    post_heartbeat(api_key: Fabricate(:api_key, user: Discourse.system_user))

    expect(response.status).to eq(200)
  end

  describe "server_id" do
    it "answers unknown_server for a server_id that is not in gtmc_servers and records nothing" do
      post_heartbeat(body: heartbeat_body.merge(server_id: "creative"))

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("status" => "unknown_server")
      get "/gtmc/status.json"
      expect(response.parsed_body["servers"].map { |server| server["server_id"] }).to eq(
        ["survival"],
      )
      expect(response.parsed_body["servers"].first["online"]).to eq(false)
    end

    it "answers unknown_server for every server_id when gtmc_servers is empty" do
      SiteSetting.gtmc_servers = "[]"

      post_heartbeat

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("status" => "unknown_server")
    end

    it "answers unknown_server for an entry whose server_id breaks the format" do
      SiteSetting.gtmc_servers = [
        { server_id: "Survival", name: "生存服", address: "survival.gtmc.test" },
      ].to_json

      post_heartbeat(body: heartbeat_body.merge(server_id: "Survival"))

      expect(response.parsed_body).to eq("status" => "unknown_server")
    end

    it "rejects a heartbeat without server_id" do
      post_heartbeat(body: heartbeat_body.except(:server_id))

      expect(response.status).to eq(400)
    end

    it "rejects a server_id that is not a string" do
      post_heartbeat(body: heartbeat_body.merge(server_id: 1))

      expect(response.status).to eq(400)
    end
  end

  describe "rejected callers" do
    it "rejects a request without an API key" do
      post_heartbeat(api_key: nil)

      expect(response.status).to eq(403)
    end

    it "rejects a key that only has an unrelated scope" do
      topics_read_key =
        Fabricate(
          :api_key,
          user: Discourse.system_user,
          api_key_scopes: [Fabricate.build(:api_key_scope, resource: "topics", action: "read")],
        )

      post_heartbeat(api_key: topics_read_key)

      expect(response.status).to eq(403)
    end

    it "rejects a gtmc:server key that belongs to a non-admin user" do
      post_heartbeat(api_key: gtmc_server_api_key(owner: user), username: user.username)

      expect(response.status).to eq(403)
    end

    it "rejects a signed-in admin using a browser session instead of an API key" do
      sign_in(admin)

      post_heartbeat(api_key: nil)

      expect(response.status).to eq(403)
    end

    it "does not record anything when the caller is rejected" do
      post_heartbeat(api_key: nil)

      expect(status_of("survival")["online"]).to eq(false)
    end
  end

  describe "invalid heartbeat bodies" do
    it "rejects a negative player count" do
      post_heartbeat(body: heartbeat_body.merge(players_online: -1))

      expect(response.status).to eq(400)
    end

    it "rejects a player count sent as a string" do
      post_heartbeat(body: heartbeat_body.merge(players_max: "20"))

      expect(response.status).to eq(400)
    end

    it "rejects player_names that is not an array" do
      post_heartbeat(body: heartbeat_body.merge(player_names: "Steve"))

      expect(response.status).to eq(400)
    end

    it "rejects a player name longer than Minecraft allows" do
      post_heartbeat(body: heartbeat_body.merge(player_names: ["A" * 17]))

      expect(response.status).to eq(400)
    end

    it "rejects a missing version" do
      post_heartbeat(body: heartbeat_body.except(:version))

      expect(response.status).to eq(400)
    end

    it "rejects a negative tps" do
      post_heartbeat(body: heartbeat_body.merge(tps: -1))

      expect(response.status).to eq(400)
    end
  end

  describe "when gtmc_enabled is off" do
    before { SiteSetting.gtmc_enabled = false }

    it "returns 404 to a global key" do
      post_heartbeat(api_key: Fabricate(:api_key, user: Discourse.system_user))

      expect(response.status).to eq(404)
    end

    # Discourse 只对已启用的插件提供它注册的作用域，并且在插件的 requires_plugin 检查之前
    # 就校验 API Key，所以只勾了 gtmc:server 的 Key 拿到的是 403 而不是 404。
    it "returns 403 to a gtmc:server key because the scope disappears with the plugin" do
      post_heartbeat

      expect(response.status).to eq(403)
    end
  end
end
