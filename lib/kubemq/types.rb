# frozen_string_literal: true

module KubeMQ
  # Transport connection lifecycle states.
  #
  # Used by the internal {Transport::ConnectionStateMachine} to track
  # the gRPC channel state. Inspect via {BaseClient} diagnostics.
  #
  # @see Transport::ConnectionStateMachine
  module ConnectionState
    # Initial state before any connection attempt.
    IDLE = :idle
    # A connection attempt is in progress.
    CONNECTING = :connecting
    # Connected and ready to send/receive messages.
    READY = :ready
    # Disconnected and attempting to reconnect.
    RECONNECTING = :reconnecting
    # Permanently closed; no further operations are possible.
    CLOSED = :closed
  end

  # Numeric subscription type identifiers sent over the wire.
  #
  # Mapped to the protobuf +Subscribe.SubscribeTypeData+ enum.
  # Application code typically does not use these directly — pass
  # subscription objects to +subscribe_to_*+ methods instead.
  #
  # @api private
  module SubscribeType
    # Unspecified subscription type.
    UNDEFINED = 0
    # Real-time fire-and-forget events.
    EVENTS = 1
    # Durable events with replay capability.
    EVENTS_STORE = 2
    # Request/reply commands.
    COMMANDS = 3
    # Request/reply queries.
    QUERIES = 4
  end

  # Numeric request type identifiers for the CQ (commands/queries) pattern.
  #
  # Mapped to the protobuf +Request.RequestTypeData+ enum.
  #
  # @api private
  module RequestType
    # Unspecified request type.
    UNKNOWN = 0
    # A command (fire-and-confirm) request.
    COMMAND = 1
    # A query (request/response with data) request.
    QUERY = 2
  end

  # String channel type identifiers used by channel management operations.
  #
  # Pass these constants to {BaseClient#create_channel},
  # {BaseClient#delete_channel}, and {BaseClient#list_channels}.
  #
  # @example
  #   client.list_channels(channel_type: KubeMQ::ChannelType::EVENTS)
  #
  # @see BaseClient#create_channel
  # @see BaseClient#delete_channel
  # @see BaseClient#list_channels
  module ChannelType
    # Pub/sub fire-and-forget events.
    EVENTS = 'events'
    # Durable events with persistence and replay.
    EVENTS_STORE = 'events_store'
    # Request/reply commands.
    COMMANDS = 'commands'
    # Request/reply queries.
    QUERIES = 'queries'
    # Message queues with acknowledgement.
    QUEUES = 'queues'
  end
end
