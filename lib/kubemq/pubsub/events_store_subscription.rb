# frozen_string_literal: true

module KubeMQ
  module PubSub
    # Start-position constants for events store subscriptions.
    #
    # Use with {EventsStoreSubscription#start_position} to control
    # where the broker begins replaying persisted events.
    #
    # @see EventsStoreSubscription
    module EventStoreStartPosition
      # Receive only events published after the subscription starts.
      START_NEW_ONLY = 1
      # Replay from the first event ever stored on the channel.
      START_FROM_FIRST = 2
      # Replay from the most recent event on the channel.
      START_FROM_LAST = 3
      # Replay from a specific sequence number (set via +start_position_value+).
      START_AT_SEQUENCE = 4
      # Replay from a specific Unix timestamp in nanoseconds (set via +start_position_value+).
      START_AT_TIME = 5
      # Replay events stored within the last N seconds (set via +start_position_value+).
      START_AT_TIME_DELTA = 6
    end

    # Configuration for subscribing to durable events store channels.
    #
    # Unlike {EventsSubscription}, events store subscriptions support
    # replay from a historical position. Pass to
    # {PubSubClient#subscribe_to_events_store} with a block to receive
    # {EventStoreReceived} messages.
    #
    # @example Subscribe from the beginning
    #   sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    #     channel: "orders.created",
    #     start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST
    #   )
    #   client.subscribe_to_events_store(sub) { |event| puts event.body }
    #
    # @example Subscribe from a specific sequence
    #   sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    #     channel: "orders.created",
    #     start_position: KubeMQ::PubSub::EventStoreStartPosition::START_AT_SEQUENCE,
    #     start_position_value: 42
    #   )
    #
    # @see PubSubClient#subscribe_to_events_store
    # @see EventStoreStartPosition
    # @see EventStoreReceived
    class EventsStoreSubscription
      # @!attribute [rw] channel
      #   @return [String] channel name to subscribe to
      # @!attribute [rw] group
      #   @return [String, nil] consumer group for load-balanced delivery
      # @!attribute [rw] start_position
      #   @return [Integer] one of the {EventStoreStartPosition} constants
      # @!attribute [rw] start_position_value
      #   @return [Integer] sequence number, Unix timestamp, or delta depending on +start_position+
      attr_accessor :channel, :group, :start_position, :start_position_value

      # @param channel [String] channel name (required)
      # @param start_position [Integer] one of the {EventStoreStartPosition} constants (required)
      # @param start_position_value [Integer] context value for the chosen start position (default: +0+)
      # @param group [String, nil] consumer group name (default: +nil+)
      def initialize(channel:, start_position:, start_position_value: 0, group: nil)
        @channel = channel
        @start_position = start_position
        @start_position_value = start_position_value
        @group = group
      end

      # Returns the subscribe type constant for the transport layer.
      #
      # @return [Integer] {SubscribeType::EVENTS_STORE}
      # @api private
      def subscribe_type
        SubscribeType::EVENTS_STORE
      end
    end
  end
end
