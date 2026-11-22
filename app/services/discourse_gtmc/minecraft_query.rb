# frozen_string_literal: true

require "io/wait"
require "socket"

module DiscourseGtmc
  # Minecraft 的 Query 协议（UDP，server.properties 里 enable-query=true），拿完整的在线名单。
  # 协议见 https://minecraft.wiki/w/Query ：先握手拿 challenge token，再用它请求 full stat。
  #
  # 由定时任务调用，所以每次收包都有超时：卡住会拖住 mini_scheduler 的其他任务。
  class MinecraftQuery
    class Error < StandardError
    end

    # host_port 是服务器的游戏端口（server-port），可能和 query.port 不同；拿不到时为 nil
    Result = Data.define(:version, :players_online, :players_max, :player_names, :host_port)

    MAGIC = "\xFE\xFD".b
    TYPE_HANDSHAKE = 9
    TYPE_STAT = 0
    # 协议要求 session id 每个字节只用低 4 位
    SESSION_ID_MASK = 0x0F0F0F0F
    # 响应开头：type(1) + session id(4) + "splitnum\0\x80\0"(11)
    STAT_HEADER_BYTES = 16
    PLAYERS_SEPARATOR = "\x01player_\x00\x00".b
    MAX_PACKET_BYTES = 65_535
    DEFAULT_TIMEOUT_SECONDS = 2

    def self.fetch(host, port, timeout: DEFAULT_TIMEOUT_SECONDS)
      session_id = SecureRandom.random_number(2**31) & SESSION_ID_MASK
      address = Addrinfo.udp(host, port)
      socket = UDPSocket.new(address.afamily)
      begin
        # connect 之后只收这个地址发来的包
        socket.connect(address.ip_address, address.ip_port)

        socket.send(MAGIC + [TYPE_HANDSHAKE, session_id].pack("CN"), 0)
        token = parse_handshake(receive(socket, timeout), session_id)

        socket.send(MAGIC + [TYPE_STAT, session_id, token].pack("CNl>") + "\x00\x00\x00\x00".b, 0)
        parse_full_stat(receive(socket, timeout), session_id)
      ensure
        socket.close
      end
    rescue SocketError, SystemCallError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    # challenge token 是 ASCII 十进制数字加 NUL，可能是负数
    def self.parse_handshake(data, session_id)
      check_header(data, TYPE_HANDSHAKE, session_id)
      Integer(data.byteslice(5..).delete("\x00"), 10)
    rescue ArgumentError
      raise Error, "bad challenge token"
    end

    def self.parse_full_stat(data, session_id)
      check_header(data, TYPE_STAT, session_id)
      body = data.byteslice(STAT_HEADER_BYTES..) || "".b
      kv_part, players_part = body.split(PLAYERS_SEPARATOR, 2)
      raise Error, "no player section" if players_part.nil?

      # 键值对都以 NUL 结尾，最后是一个空键；split 会丢掉末尾的空串，值为空的键补成 ""
      fields = kv_part.split("\x00").each_slice(2).to_h { |key, value| [text(key), text(value)] }
      player_names = players_part.split("\x00").map { |name| text(name) }.reject(&:empty?)

      Result.new(
        version: fields["version"].to_s,
        players_online: Integer(fields["numplayers"], 10),
        players_max: Integer(fields["maxplayers"], 10),
        player_names: player_names,
        host_port: port_or_nil(fields["hostport"]),
      )
    rescue ArgumentError, TypeError
      raise Error, "bad player counts"
    end

    def self.port_or_nil(value)
      port = Integer(value.to_s, 10, exception: false)
      port if port&.between?(1, 65_535)
    end
    private_class_method :port_or_nil

    def self.check_header(data, type, session_id)
      if data.bytesize < 5 || data.getbyte(0) != type ||
           data.byteslice(1, 4).unpack1("N") != session_id
        raise Error, "unexpected response"
      end
    end
    private_class_method :check_header

    def self.receive(socket, timeout)
      raise Error, "timed out after #{timeout}s" if !socket.wait_readable(timeout)
      socket.recv(MAX_PACKET_BYTES).b
    end
    private_class_method :receive

    def self.text(bytes)
      bytes.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    end
    private_class_method :text
  end
end
