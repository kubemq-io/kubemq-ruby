# frozen_string_literal: true

module KubeMQ
  module CQ
    # Configuration for subscribing to command requests.
    #
    # Pass to {CQClient#subscribe_to_commands} along with a block to
    # receive {CommandReceived} messages. Use {#group} for load-balanced
    # delivery across multiple responders.
    #
    # @example
    #   sub = KubeMQ::CQ::CommandsSubscription.new(
    #     channel: "commands.user.create",
    #     group: "user-service"
    #   )
    #   client.subscribe_to_commands(sub) do |cmd|
    #     # process and respond
    #   end
    #
    # @see CQClient#subscribe_to_commands
    # @see CommandReceived
    class CommandsSubscription
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
      # @return [Integer] {SubscribeType::COMMANDS}
      # @api private
      def subscribe_type
        SubscribeType::COMMANDS
      end
    end
  end
end
