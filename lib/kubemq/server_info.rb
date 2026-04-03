# frozen_string_literal: true

module KubeMQ
  # Information about a KubeMQ broker returned by {BaseClient#ping}.
  #
  # @example
  #   info = client.ping
  #   puts "Connected to #{info.host} v#{info.version}, up #{info.server_up_time_seconds}s"
  #
  # @see BaseClient#ping
  class ServerInfo
    # @!attribute [r] host
    #   @return [String] broker hostname or IP address
    # @!attribute [r] version
    #   @return [String] broker software version
    # @!attribute [r] server_start_time
    #   @return [Integer] broker start time as a Unix timestamp
    # @!attribute [r] server_up_time_seconds
    #   @return [Integer] broker uptime in seconds
    attr_reader :host, :version, :server_start_time, :server_up_time_seconds

    # Creates a new ServerInfo instance.
    #
    # @param host [String] broker hostname or IP address
    # @param version [String] broker software version
    # @param server_start_time [Integer] broker start time as a Unix timestamp
    # @param server_up_time_seconds [Integer] broker uptime in seconds
    def initialize(host:, version:, server_start_time:, server_up_time_seconds:)
      @host = host
      @version = version
      @server_start_time = server_start_time
      @server_up_time_seconds = server_up_time_seconds
    end

    # Constructs a {ServerInfo} from a protobuf ping result.
    #
    # @api private
    # @param ping_result [Kubemq::PingResult] protobuf ping response
    # @return [ServerInfo]
    def self.from_proto(ping_result)
      new(
        host: ping_result.Host,
        version: ping_result.Version,
        server_start_time: ping_result.ServerStartTime,
        server_up_time_seconds: ping_result.ServerUpTimeSeconds
      )
    end

    # Returns a human-readable summary of the server information.
    #
    # @return [String]
    def to_s
      "ServerInfo(host=#{@host}, version=#{@version}, " \
        "up_time=#{@server_up_time_seconds}s)"
    end
  end
end
