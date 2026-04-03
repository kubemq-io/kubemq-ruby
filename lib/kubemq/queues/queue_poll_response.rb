# frozen_string_literal: true

module KubeMQ
  module Queues
    # Response from polling a queue channel via {QueuesClient#poll}.
    #
    # Contains the received {#messages} and provides batch transaction
    # actions ({#ack_all}, {#nack_all}, {#requeue_all}) as well as
    # range-based variants for partial acknowledgement.
    #
    # @example Acknowledge all messages
    #   response = client.poll(request)
    #   unless response.error?
    #     response.messages.each { |msg| process(msg.body) }
    #     response.ack_all
    #   end
    #
    # @see QueuesClient#poll
    # @see QueuePollRequest
    # @see QueueMessageReceived
    class QueuePollResponse
      # @!attribute [r] transaction_id
      #   @return [String] broker-assigned transaction identifier
      # @!attribute [r] messages
      #   @return [Array<QueueMessageReceived>] received messages
      # @!attribute [r] error
      #   @return [String, nil] error description if the poll failed
      # @!attribute [r] active_offsets
      #   @return [Array<Integer>] currently active message offsets
      # @!attribute [r] transaction_complete
      #   @return [Boolean] whether the transaction has been finalized
      attr_reader :transaction_id, :messages, :error, :active_offsets, :transaction_complete

      # @param transaction_id [String] broker-assigned transaction ID
      # @param messages [Array<QueueMessageReceived>] received messages
      # @param error [String, nil] error description on failure
      # @param active_offsets [Array<Integer>] active message offsets
      # @param transaction_complete [Boolean] whether the transaction is complete
      # @param action_proc [Proc, nil] internal callback for transaction actions
      # @api private
      def initialize(transaction_id:, messages:, error:, active_offsets:,
                     transaction_complete:, action_proc: nil)
        @transaction_id = transaction_id
        @messages = messages
        @error = error
        @active_offsets = active_offsets
        @transaction_complete = transaction_complete
        @action_proc = action_proc
      end

      # Returns whether the poll resulted in an error.
      #
      # @return [Boolean] +true+ if an error occurred
      def error?
        !@error.nil? && !@error.empty?
      end

      # Acknowledges all messages in this poll transaction.
      #
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def ack_all
        send_action(:AckAll)
      end

      # Acknowledges a specific range of messages by sequence number.
      #
      # @param sequence_range [Array<Integer>] sequence numbers to acknowledge
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def ack_range(sequence_range:)
        send_action(:AckRange, sequence_range: sequence_range)
      end

      # Negative-acknowledges all messages in this poll transaction.
      #
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def nack_all
        send_action(:NAckAll)
      end

      # Negative-acknowledges a specific range of messages by sequence number.
      #
      # @param sequence_range [Array<Integer>] sequence numbers to nack
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def nack_range(sequence_range:)
        send_action(:NAckRange, sequence_range: sequence_range)
      end

      # Requeues all messages in this poll transaction to a different channel.
      #
      # @param channel [String] destination channel name
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def requeue_all(channel:)
        send_action(:ReQueueAll, channel: channel)
      end

      # Requeues a specific range of messages to a different channel.
      #
      # @param channel [String] destination channel name
      # @param sequence_range [Array<Integer>] sequence numbers to requeue
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound or the broker rejects the action
      def requeue_range(channel:, sequence_range:)
        send_action(:ReQueueRange, channel: channel, sequence_range: sequence_range)
      end

      # Queries whether the poll transaction is still active on the broker.
      #
      # @return [Boolean] +true+ if the transaction is still active, +false+ if completed or no receiver
      # rubocop:disable Naming/PredicateMethod -- mirrors broker transaction state, not a Ruby predicate name
      def transaction_status
        return false if @transaction_complete
        return false unless @action_proc

        response = @action_proc.call(:TransactionStatus)
        return false if response.nil?

        !response.TransactionComplete
      end
      # rubocop:enable Naming/PredicateMethod

      private

      def send_action(type, channel: nil, sequence_range: [])
        raise TransactionError, 'No downstream receiver bound' unless @action_proc

        response = @action_proc.call(type, channel: channel, sequence_range: sequence_range)
        return if response.nil?

        raise TransactionError.new(response.Error, operation: 'downstream_action') if response.IsError
      end
    end
  end
end
