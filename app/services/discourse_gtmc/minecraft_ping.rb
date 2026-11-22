# frozen_string_literal: true

require "io/wait"
require "socket"

module DiscourseGtmc
  # Minecraft 的 Server List Ping（TCP，客户端刷服务器列表用的那个），这里只用来取服务器图标（server-icon.png）。
  # Query 协议不带图标，所以另走一趟。协议见 https://minecraft.wiki/w/Java_Edition_protocol/Server_List_Ping
  #
  # 1.7 起的服都支持。Forge 服的响应里带完整的模组列表，GTNH 这种整合包能有几十 KB，
  # 所以要循环读到长度够为止，并且整体有超时和大小上限：它跑在 mini_scheduler 的定时任务里。
  class MinecraftPing
    class Error < StandardError
    end

    DEFAULT_TIMEOUT_SECONDS = 3
    MAX_RESPONSE_BYTES = 2 * 1024 * 1024
    MAX_FAVICON_BYTES = 64 * 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    FAVICON_PREFIX = "data:image/png;base64,"
    # 状态查询不看协议版本，惯例传 -1
    PROTOCOL_VERSION = -1
    NEXT_STATE_STATUS = 1

    # 返回 PNG 的字节；服务器没设图标、或图标不是合格的 PNG 时返回 nil。连不上、超时、响应不对时抛 Error。
    def self.fetch_favicon(host, port, timeout: DEFAULT_TIMEOUT_SECONDS)
      status = fetch_status(host, port, timeout:)
      decode_favicon(status["favicon"])
    end

    def self.fetch_status(host, port, timeout: DEFAULT_TIMEOUT_SECONDS)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      socket = Socket.tcp(host, port, connect_timeout: timeout)
      begin
        handshake =
          varint(0x00) + varint(PROTOCOL_VERSION) + string(host) + [port].pack("n") +
            varint(NEXT_STATE_STATUS)
        socket.write(packet(handshake) + packet(varint(0x00)))

        reader = Reader.new(socket, deadline)
        length = reader.read_varint
        raise Error, "response too large" if length > MAX_RESPONSE_BYTES
        body = reader.read_bytes(length)

        payload = StringIO.new(body)
        raise Error, "unexpected packet" if read_varint_from(payload) != 0x00
        json_length = read_varint_from(payload)
        json = payload.read(json_length).to_s
        raise Error, "truncated status" if json.bytesize != json_length

        status = JSON.parse(json.force_encoding(Encoding::UTF_8).scrub)
        raise Error, "status is not an object" if !status.is_a?(Hash)
        status
      ensure
        socket.close
      end
    rescue JSON::ParserError
      raise Error, "status is not JSON"
    rescue SocketError, SystemCallError, IOError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    # 1.7.10 的服给的 base64 里可能夹着换行，先去掉空白再按宽松模式解码
    def self.decode_favicon(favicon)
      return if !favicon.is_a?(String) || !favicon.start_with?(FAVICON_PREFIX)
      png = Base64.decode64(favicon.delete_prefix(FAVICON_PREFIX).gsub(/\s+/, ""))
      return if png.bytesize > MAX_FAVICON_BYTES || !png.start_with?(PNG_SIGNATURE)
      png
    end

    def self.packet(payload)
      varint(payload.bytesize) + payload
    end
    private_class_method :packet

    def self.string(value)
      bytes = value.b
      varint(bytes.bytesize) + bytes
    end
    private_class_method :string

    # 负数按 32 位无符号编码，-1 是 5 个字节
    def self.varint(value)
      value &= 0xFFFF_FFFF
      bytes = +"".b
      loop do
        byte = value & 0x7F
        value >>= 7
        bytes << (value.zero? ? byte : byte | 0x80).chr
        return bytes if value.zero?
      end
    end
    private_class_method :varint

    def self.read_varint_from(io)
      value = 0
      5.times do |index|
        byte = io.getbyte
        raise Error, "truncated varint" if byte.nil?
        value |= (byte & 0x7F) << (7 * index)
        return value if byte & 0x80 == 0
      end
      raise Error, "varint too long"
    end
    private_class_method :read_varint_from

    # 在一个总的截止时间内从 TCP 连接里读：响应会分好几段到
    class Reader
      def initialize(socket, deadline)
        @socket = socket
        @deadline = deadline
      end

      def read_varint
        value = 0
        5.times do |index|
          byte = read_bytes(1).getbyte(0)
          value |= (byte & 0x7F) << (7 * index)
          return value if byte & 0x80 == 0
        end
        raise Error, "varint too long"
      end

      def read_bytes(count)
        buffer = +"".b
        while buffer.bytesize < count
          remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Error, "timed out" if remaining <= 0 || !@socket.wait_readable(remaining)
          chunk = @socket.read_nonblock(count - buffer.bytesize, exception: false)
          raise Error, "connection closed early" if chunk.nil?
          buffer << chunk if chunk.is_a?(String)
        end
        buffer
      end
    end
    private_constant :Reader
  end
end
