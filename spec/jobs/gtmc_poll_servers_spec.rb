# frozen_string_literal: true

RSpec.describe Jobs::GtmcPollServers do
  let(:polled_server) do
    {
      server_id: "creative",
      name: "创造服",
      addresses: [{ address: "creative.gtmc.test" }],
      icon: "gtmc-hammer",
      query_address: "10.0.0.5:25581",
    }
  end
  let(:heartbeat_server) do
    {
      server_id: "survival",
      name: "生存服",
      addresses: [{ address: "survival.gtmc.test" }],
      icon: "gtmc-bricks",
    }
  end
  let(:query_result) do
    DiscourseGtmc::MinecraftQuery::Result.new(
      version: "1.21.11",
      players_online: 2,
      players_max: 20,
      player_names: %w[Steve Alex],
      host_port: 25_580,
    )
  end
  let(:png) { "\x89PNG\r\n\x1A\n".b + "pixels".b }

  def status_by_server_id
    DiscourseGtmc::ServerStatus.current(include_players: true)[:servers].index_by do |server|
      server[:server_id]
    end
  end

  before do
    # 默认没有图标；要测图标的用例自己再 stub
    DiscourseGtmc::MinecraftPing.stubs(:fetch_favicon).returns(nil)
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

  it "remembers the queried players for the newcomer panel" do
    DiscourseGtmc::MinecraftQuery.stubs(:fetch).returns(query_result)

    described_class.new.execute({})

    expect(DiscourseGtmc::SeenPlayer.pluck(:mc_name, :first_server_id)).to contain_exactly(
      %w[Steve creative],
      %w[Alex creative],
    )
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

  describe "server icons" do
    before { DiscourseGtmc::MinecraftQuery.stubs(:fetch).returns(query_result) }

    it "fetches the icon from the game port and keeps it" do
      DiscourseGtmc::MinecraftPing
        .expects(:fetch_favicon)
        .with("10.0.0.5", 25_580)
        .returns(png)
        .once

      described_class.new.execute({})
      described_class.new.execute({})

      expect(DiscourseGtmc::ServerFavicon.png("creative")).to eq(png)
      expect(status_by_server_id["creative"][:favicon_url]).to match(
        %r{\A/gtmc/servers/creative/icon\.png\?v=[0-9a-f]{12}\z},
      )
    end

    it "fetches it again after an hour" do
      DiscourseGtmc::MinecraftPing.expects(:fetch_favicon).returns(png).twice

      described_class.new.execute({})
      freeze_time(61.minutes.from_now) { described_class.new.execute({}) }
    end

    it "keeps showing the icon while the server is offline" do
      DiscourseGtmc::MinecraftPing.stubs(:fetch_favicon).returns(png)
      described_class.new.execute({})

      freeze_time(10.minutes.from_now) do
        creative = status_by_server_id["creative"]
        expect(creative[:online]).to eq(false)
        expect(creative[:favicon_url]).to be_present
      end
    end

    it "keeps the old icon when fetching a new one fails" do
      DiscourseGtmc::MinecraftPing.stubs(:fetch_favicon).returns(png)
      described_class.new.execute({})
      DiscourseGtmc::MinecraftPing.stubs(:fetch_favicon).raises(DiscourseGtmc::MinecraftPing::Error)

      freeze_time(61.minutes.from_now) { described_class.new.execute({}) }

      expect(DiscourseGtmc::ServerFavicon.png("creative")).to eq(png)
    end

    it "skips the icon when Query does not say which port the game is on" do
      DiscourseGtmc::MinecraftQuery.stubs(:fetch).returns(query_result.with(host_port: nil))
      DiscourseGtmc::MinecraftPing.expects(:fetch_favicon).never

      described_class.new.execute({})
    end
  end
end
