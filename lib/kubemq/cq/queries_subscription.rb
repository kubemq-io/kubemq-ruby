# frozen_string_literal: true

module KubeMQ
  module CQ
    # Configuration for subscribing to query requests.
    #
    # Pass to {CQClient#subscribe_to_queries} along with a block to
    # receive {QueryReceived} messages. Use {#group} for load-balanced
    # delivery across multiple responders.
    #
    # @example
    #   sub = KubeMQ::CQ::QueriesSubscription.new(
    #     channel: "queries.user.get",
    #     group: "user-service"
    #   )
    #   client.subscribe_to_queries(sub) do |query|
    #     # process and respond
    #   end
    #
    # @see CQClient#subscribe_to_queries
    # @see QueryReceived
    class QueriesSubscription
      # @!attribute [rw] channel
      #   @return [String] channel name to subscribe to
      # @!attribute [rw] group
      #   @return [String, nil] consumer group for load-balanced delivery
      attr_accessor :channel, :group

      # @param channel [String] channel name (required)
      # @param group [String, nil] consumer group name (default: +nil+)
      def initialize(channel:, group: nil)
        @channel = channel
        @group = group
      end

      # Returns the subscribe type constant for the transport layer.
      #
      # @return [Integer] {SubscribeType::QUERIES}
      # @api private
      def subscribe_type
        SubscribeType::QUERIES
      end
    end
  end
end
