# frozen_string_literal: true

RSpec.describe DiscourseGtmc::MinecraftPing do
  let(:png) { "\x89PNG\r\n\x1A\n".b + "pixels".b }

  def varint(value)
    bytes = +"".b
    loop do
      byte = value & 0x7F
      value >>= 7
      bytes << (value.zero? ? byte : byte | 0x80).chr
      return bytes if value.zero?
    end
  end

  def status_response(status)
    json = status.to_json.b
    body = varint(0) + varint(json.bytesize) + json
    varint(body.bytesize) + body
  end

  # 本机起一个 TCP 服务端，把响应拆成两段、中间停一下再发：真实的 Forge 服就是分好几段到的
  def serve_once(response)
    server = TCPServer.new("127.0.0.1", 0)
    thread =
      Thread.new do
        client = server.accept
        client.readpartial(1024)
        half = response.bytesize / 2
        client.write(response.byteslice(0, half))
        sleep 0.05
        client.write(response.byteslice(half..))
        client.close
      end
    yield server.addr[1]
  ensure
    thread&.join(1)
    server&.close
  end

  describe ".fetch_favicon" do
    it "reads a status response that arrives in pieces" do
      favicon = "data:image/png;base64,#{Base64.strict_encode64(png)}"
      response =
        status_response(
          "description" => "x" * 5000,
          "favicon" => favicon,
          "forgeData" => {
            "mods" => Array.new(300) { |i| { "modId" => "mod#{i}" } },
          },
        )

      serve_once(response) do |port|
        expect(described_class.fetch_favicon("127.0.0.1", port, timeout: 2)).to eq(png)
      end
    end

    it "returns nil when the server has no icon" do
      serve_once(status_response("description" => "hi")) do |port|
        expect(described_class.fetch_favicon("127.0.0.1", port, timeout: 2)).to be_nil
      end
    end

    it "gives up when nobody is listening" do
      port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }

      expect { described_class.fetch_favicon("127.0.0.1", port, timeout: 1) }.to raise_error(
        described_class::Error,
      )
    end
  end

  describe ".decode_favicon" do
    it "accepts base64 with line breaks, as 1.7.10 servers send it" do
      encoded = Base64.encode64(png) # 每 60 个字符一个换行
      expect(described_class.decode_favicon("data:image/png;base64,#{encoded}")).to eq(png)
    end

    it "rejects anything that is not a PNG" do
      expect(
        described_class.decode_favicon("data:image/png;base64,#{Base64.strict_encode64("<svg/>")}"),
      ).to be_nil
      expect(described_class.decode_favicon("https://example.com/icon.png")).to be_nil
      expect(described_class.decode_favicon(nil)).to be_nil
    end
  end
end
