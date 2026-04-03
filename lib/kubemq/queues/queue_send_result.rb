# frozen_string_literal: true

module KubeMQ
  module Queues
    # Result returned after sending a queue message via
    # {QueuesClient#send_queue_message}, {QueuesClient#send_queue_message_stream},
    # or {UpstreamSender#publish}.
    #
    # Check {#error?} to detect failures. On success, timing fields indicate
    # when the message was accepted and any policy-driven delays or expirations.
    #
    # @see QueuesClient#send_queue_message
    # @see UpstreamSender#publish
    # @see QueueMessage
    class QueueSendResult
      # @!attribute [r] id
      #   @return [String] message identifier
      # @!attribute [r] sent_at
      #   @return [Integer] broker-assigned send timestamp (Unix nanoseconds)
      # @!attribute [r] expiration_at
      #   @return [Integer] message expiration timestamp (Unix nanoseconds); +0+ if none
      # @!attribute [r] delayed_to
      #   @return [Integer] message visibility timestamp (Unix nanoseconds); +0+ if no delay
      # @!attribute [r] error
      #   @return [String, nil] error description if the send failed
      attr_reader :id, :sent_at, :expiration_at, :delayed_to, :error

      # @param id [String] message identifier
      # @param sent_at [Integer] send timestamp (default: +0+)
      # @param expiration_at [Integer] expiration timestamp (default: +0+)
      # @param delayed_to [Integer] visibility delay timestamp (default: +0+)
      # @param error [String, nil] error description on failure
      def initialize(id:, sent_at: 0, expiration_at: 0, delayed_to: 0, error: nil)
        @id = id
        @sent_at = sent_at
        @expiration_at = expiration_at
        @delayed_to = delayed_to
        @error = error
      end

      # Returns whether the send resulted in an error.
      #
      # @return [Boolean] +true+ if an error occurred
      def error?
        !@error.nil? && !@error.empty?
      end
    end
  end
end
