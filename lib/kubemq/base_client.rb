# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  # Base class for all KubeMQ client types.
  #
  # Provides shared connection management, channel CRUD operations, and
  # lifecycle methods. Not intended for direct instantiation — use
  # {PubSubClient}, {QueuesClient}, or {CQClient} instead.
  #
  # @note This class is thread-safe. The underlying transport and state are
  #   protected by a mutex.
  #
  # @see PubSubClient
  # @see QueuesClient
  # @see CQClient
  class BaseClient
    # @!attribute [r] config
    #   @return [Configuration] the client's resolved configuration
    # @!attribute [r] transport
    #   @return [Transport::GrpcTransport] the underlying gRPC transport
    attr_reader :config, :transport

    # Creates a new client connected to a KubeMQ broker.
    #
    # Connection is established lazily on first use, not during initialization.
    # Pass individual options or a pre-built {Configuration} object.
    #
    # @param address [String, nil] broker host:port (default: from config or +localhost:50000+)
    # @param client_id [String, nil] unique identifier for this client (auto-generated if nil)
    # @param auth_token [String, nil] bearer token for authentication
    # @param config [Configuration, nil] pre-built configuration (overrides individual options)
    # @param transport [Transport::GrpcTransport, nil] custom transport (for testing)
    # @param options [Hash] additional options forwarded to {Configuration}
    #
    # @raise [ConfigurationError] if the resolved configuration is invalid
    #
    # @example
    #   client = KubeMQ::PubSubClient.new(
    #     address: "localhost:50000",
    #     client_id: "my-publisher"
    #   )
    def initialize(address: nil, client_id: nil, auth_token: nil, config: nil, transport: nil, **options)
      @config = config || Configuration.new(
        address: address,
        client_id: client_id,
        auth_token: auth_token,
        **options
      )
      @config.validate!
      @transport = transport || Transport::GrpcTransport.new(@config)
      @closed = false
      @mutex = Mutex.new
    end

    # Pings the KubeMQ broker and returns server information.
    #
    # @return [ServerInfo] broker host, version, and uptime
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @example
    #   info = client.ping
    #   puts "Connected to #{info.host} v#{info.version}"
    def ping
      ensure_not_closed!
      @transport.ensure_connected!
      @transport.ping
    end

    # Closes the client and releases all resources.
    #
    # Cancels active subscriptions, flushes the message buffer, and closes the
    # gRPC channel. This method is idempotent — calling it multiple times is safe.
    #
    # @return [void]
    def close
      @mutex.synchronize { @closed = true }
      @transport.close
    end

    # Returns whether the client has been closed.
    #
    # @return [Boolean] +true+ if {#close} has been called or the transport is closed
    def closed?
      @mutex.synchronize { @closed } || @transport.closed?
    end

    # Creates a channel on the KubeMQ broker.
    #
    # @param channel_name [String] name for the new channel
    # @param channel_type [String] one of {ChannelType}::EVENTS, EVENTS_STORE,
    #   COMMANDS, QUERIES, QUEUES
    #
    # @return [Boolean] +true+ on success
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    # @raise [ChannelError] if the broker rejects the operation
    # @raise [ValidationError] if +channel_name+ is invalid
    #
    # @see ChannelType
    def create_channel(channel_name:, channel_type:)
      ensure_not_closed!
      @transport.ensure_connected!
      Transport::ChannelManager.create_channel(
        @transport, @config.client_id, channel_name, channel_type
      )
    end

    # Deletes a channel from the KubeMQ broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @param channel_type [String] one of {ChannelType} constants
    #
    # @return [Boolean] +true+ on success
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    # @raise [ChannelError] if the broker rejects the operation
    def delete_channel(channel_name:, channel_type:)
      ensure_not_closed!
      @transport.ensure_connected!
      Transport::ChannelManager.delete_channel(
        @transport, @config.client_id, channel_name, channel_type
      )
    end

    # Lists channels of the specified type, with optional name filtering.
    #
    # @param channel_type [String] one of {ChannelType} constants
    # @param search [String, nil] substring filter for channel names
    #
    # @return [Array<ChannelInfo>] matching channels with metadata
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    # @raise [ChannelError] if the broker rejects the operation
    #
    # @example
    #   channels = client.list_channels(channel_type: KubeMQ::ChannelType::EVENTS)
    #   channels.each { |ch| puts "#{ch.name} active=#{ch.active?}" }
    def list_channels(channel_type:, search: nil)
      ensure_not_closed!
      @transport.ensure_connected!
      Transport::ChannelManager.list_channels(
        @transport, @config.client_id, channel_type, search
      )
    end

    # Purges all messages from a queue channel.
    #
    # @param channel_name [String] queue channel to purge
    #
    # @return [Hash] +{ affected_messages: Integer }+
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    def purge_queue_channel(channel_name:)
      ensure_not_closed!
      @transport.ensure_connected!
      Transport::ChannelManager.purge_queue(
        @transport, @config.client_id, channel_name
      )
    end

    private

    def ensure_not_closed!
      raise ClientClosedError if closed?
    end

    def ensure_connected!
      ensure_not_closed!
      @transport.ensure_connected!
    end
  end
end
