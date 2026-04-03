# frozen_string_literal: true

module KubeMQ
  module PubSub
    # Configuration for subscribing to real-time (non-durable) events.
    #
    # Pass to {PubSubClient#subscribe_to_events} along with a block to
    # receive {EventReceived} messages. Supports wildcard channels
    # (+*+ and +>+) and consumer groups for load balancing.
    #
    # @example
    #   sub = KubeMQ::PubSub::EventsSubscription.new(
    #     channel: "events.>",
    #     group: "workers"
    #   )
    #   client.subscribe_to_events(sub) { |event| puts event.body }
    #
    # @see PubSubClient#subscribe_to_events
    # @see EventReceived
    class EventsSubscription
      # @!attribute [rw] channel
      #   @return [String] channel name or wildcard pattern to subscribe to
      # @!attribute [rw] group
      #   @return [String, nil] consumer group for load-balanced delivery
      attr_accessor :channel, :group

      # @param channel [String] channel name or wildcard pattern (required)
      # @param group [String, nil] consumer group name (default: +nil+)
      def initialize(channel:, group: nil)
        @channel = channel
        @group = group
      end

      # Returns the subscribe type constant for the transport layer.
      #
      # @return [Integer] {SubscribeType::EVENTS}
      # @api private
      def subscribe_type
        SubscribeType::EVENTS
      end
    end
  end
end
