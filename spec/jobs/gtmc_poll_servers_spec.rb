# frozen_string_literal: true

RSpec.describe Jobs::GtmcPollServers do
  let(:polled_server) do
    {
      server_id: "creative",
      name: "创造服",
      address: "creative.gtmc.test",
      icon: "gtmc-hammer",
      query_address: "10.0.0.5:25581",
    }
  end
  let(:heartbeat_server) do
    { server_id: "survival", name: "生存服", address: "survival.gtmc.test", icon: "gtmc-bricks" }
  end
  let(:query_result) do
    DiscourseGtmc::MinecraftQuery::Result.new(
      version: "1.21.11",
      players_online: 2,
      players_max: 20,
      player_names: %w[Steve Alex],
    )
  end

  def status_by_server_id
    DiscourseGtmc::ServerStatus.current(include_players: true)[:servers].index_by do |server|
      server[:server_id]
    end
  end

  before do
    SiteSetting.gtmc_enabled = true
    SiteSetting.gtmc_servers = [polled_server, heartbeat_server].to_json
  end

  it "queries only servers with a query_address and shows them online without TPS" do
    DiscourseGtmc::MinecraftQuery
      .expects(:fetch)
      .with("10.0.0.5", 25_581)
      .returns(query_result)
      .once

    described_class.new.execute({})

    creative = status_by_server_id["creative"]
    expect(creative).to include(
      online: true,
      version: "1.21.11",
      players_online: 2,
      players_max: 20,
      tps: nil,
    )
    expect(creative[:players].map { |player| player[:mc_name] }).to eq(%w[Steve Alex])
    expect(status_by_server_id["survival"][:online]).to eq(false)
  end

  it "leaves the server offline when the query fails" do
    DiscourseGtmc::MinecraftQuery.stubs(:fetch).raises(
      DiscourseGtmc::MinecraftQuery::Error,
      "timed out",
    )

    described_class.new.execute({})

    expect(status_by_server_id["creative"][:online]).to eq(false)
  end

  it "drops player names longer than Minecraft allows" do
    DiscourseGtmc::MinecraftQuery.stubs(:fetch).returns(
      query_result.with(player_names: ["Steve", "x" * 17]),
    )

    described_class.new.execute({})

    expect(status_by_server_id["creative"][:players].map { |player| player[:mc_name] }).to eq(
      ["Steve"],
    )
  end

  it "does not query a server whose query_address is malformed" do
    SiteSetting.gtmc_servers = [
      polled_server.merge(query_address: "10.0.0.5"),
      heartbeat_server,
    ].to_json
    DiscourseGtmc::MinecraftQuery.expects(:fetch).never

    described_class.new.execute({})

    expect(status_by_server_id.keys).to contain_exactly("creative", "survival")
  end

  it "does nothing while the plugin is disabled" do
    SiteSetting.gtmc_enabled = false
    DiscourseGtmc::MinecraftQuery.expects(:fetch).never

    described_class.new.execute({})
  end

  it "never exposes the query address in status.json" do
    expect(DiscourseGtmc::ServerStatus.current(include_players: false).to_json).not_to include(
      "10.0.0.5",
    )
  end
end
