# frozen_string_literal: true

RSpec.describe DiscourseGtmc::StatusController do
  let(:offline_status) do
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

  def post_heartbeat
    api_key =
      Fabricate(
        :api_key,
        user: Discourse.system_user,
        api_key_scopes: [Fabricate.build(:api_key_scope, resource: "gtmc", action: "server")],
      )
    post "/gtmc/server/heartbeat.json",
         params: {
           version: "1.21.4-232-ver/1.21.4",
           players_online: 2,
           players_max: 20,
           player_names: %w[Steve Alex],
           tps: 19.98,
         },
         headers: {
           "Api-Key" => api_key.key,
           "Api-Username" => "system",
         },
         as: :json
    expect(response.status).to eq(200)
  end

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_heartbeat_timeout_seconds = 90
  end

  it "reports offline with every other field null before any heartbeat arrives" do
    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(offline_status)
  end

  it "reports online with the reported numbers right after a heartbeat" do
    freeze_time
    post_heartbeat

    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "online" => true,
      "version" => "1.21.4-232-ver/1.21.4",
      "players_online" => 2,
      "players_max" => 20,
      "player_names" => %w[Steve Alex],
      "tps" => 19.98,
      "updated_at" => Time.zone.now.iso8601(3),
    )
  end

  it "is readable by anonymous visitors" do
    post_heartbeat

    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["online"]).to eq(true)
  end

  it "stays online while the last heartbeat is younger than the timeout" do
    freeze_time
    post_heartbeat

    freeze_time 89.seconds.from_now
    get "/gtmc/status.json"

    expect(response.parsed_body["online"]).to eq(true)
  end

  it "reports offline once no heartbeat has arrived for longer than the timeout" do
    freeze_time
    post_heartbeat

    freeze_time 91.seconds.from_now
    get "/gtmc/status.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(offline_status)
  end

  it "applies a changed timeout to a heartbeat that was already stored" do
    freeze_time
    post_heartbeat

    freeze_time 60.seconds.from_now
    SiteSetting.gtmc_heartbeat_timeout_seconds = 30
    get "/gtmc/status.json"

    expect(response.parsed_body["online"]).to eq(false)
  end

  it "returns 404 when gtmc_enabled is off" do
    SiteSetting.gtmc_enabled = false

    get "/gtmc/status.json"

    expect(response.status).to eq(404)
  end
end
