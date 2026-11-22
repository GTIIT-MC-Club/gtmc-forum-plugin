# frozen_string_literal: true

RSpec.describe DiscourseGtmc::MinecraftQuery do
  let(:session_id) { 0x01020304 }

  def full_stat(fields, player_names, session: session_id)
    kv = fields.map { |key, value| "#{key}\x00#{value}\x00" }.join
    [0, session].pack("CN").b + "splitnum\x00\x80\x00".b + kv.b + "\x00".b +
      "\x01player_\x00\x00".b + player_names.map { |name| "#{name}\x00" }.join.b + "\x00".b
  end

  let(:vanilla_fields) do
    {
      "hostname" => "A Minecraft Server",
      "gametype" => "SMP",
      "game_id" => "MINECRAFT",
      "version" => "1.21.11",
      "plugins" => "",
      "map" => "world",
      "numplayers" => "2",
      "maxplayers" => "20",
      "hostport" => "25565",
      "hostip" => "0.0.0.0",
    }
  end

  describe ".parse_handshake" do
    it "reads the challenge token, including negative ones" do
      expect(
        described_class.parse_handshake([9, session_id].pack("CN") + "9513307\x00", session_id),
      ).to eq(9_513_307)
      expect(
        described_class.parse_handshake([9, session_id].pack("CN") + "-42\x00", session_id),
      ).to eq(-42)
    end

    it "rejects a reply for another session" do
      expect {
        described_class.parse_handshake([9, 7].pack("CN") + "1\x00", session_id)
      }.to raise_error(described_class::Error)
    end
  end

  describe ".parse_full_stat" do
    it "reads the version, player counts and every player name" do
      result =
        described_class.parse_full_stat(full_stat(vanilla_fields, %w[Steve Alex]), session_id)

      expect(result).to eq(
        described_class::Result.new(
          version: "1.21.11",
          players_online: 2,
          players_max: 20,
          player_names: %w[Steve Alex],
          host_port: 25_565,
        ),
      )
    end

    it "returns an empty name list when nobody is online" do
      result =
        described_class.parse_full_stat(
          full_stat(vanilla_fields.merge("numplayers" => "0"), []),
          session_id,
        )

      expect(result.players_online).to eq(0)
      expect(result.player_names).to eq([])
    end

    it "rejects a reply without the player section" do
      data = full_stat(vanilla_fields, []).sub("\x01player_\x00\x00".b, "".b)

      expect { described_class.parse_full_stat(data, session_id) }.to raise_error(
        described_class::Error,
      )
    end

    it "rejects player counts that are not numbers" do
      data = full_stat(vanilla_fields.merge("numplayers" => "lots"), [])

      expect { described_class.parse_full_stat(data, session_id) }.to raise_error(
        described_class::Error,
      )
    end

    it "rejects a reply for another session" do
      expect {
        described_class.parse_full_stat(full_stat(vanilla_fields, [], session: 99), session_id)
      }.to raise_error(described_class::Error)
    end
  end

  describe ".fetch" do
    it "gives up when the server does not answer" do
      silent_socket = UDPSocket.new
      silent_socket.bind("127.0.0.1", 0)

      expect {
        described_class.fetch("127.0.0.1", silent_socket.addr[1], timeout: 0.1)
      }.to raise_error(described_class::Error, /timed out/)
    ensure
      silent_socket&.close
    end
  end
end
