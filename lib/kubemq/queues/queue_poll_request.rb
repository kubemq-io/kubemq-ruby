# frozen_string_literal: true

module KubeMQ
  module Queues
    # Internal constants for downstream queue request types.
    #
    # Used by the transport layer to encode transaction actions sent
    # over the downstream gRPC stream.
    #
    # @api private
    module DownstreamRequestType
      # Poll for new messages.
      GET = 1
      # Acknowledge all messages in the transaction.
      ACK_ALL = 2
      # Acknowledge a specific range of messages by sequence.
      ACK_RANGE = 3
      # Negative-acknowledge all messages in the transaction.
      NACK_ALL = 4
      # Negative-acknowledge a specific range of messages by sequence.
      NACK_RANGE = 5
      # Requeue all messages to a different channel.
      REQUEUE_ALL = 6
      # Requeue a specific range of messages to a different channel.
      REQUEUE_RANGE = 7
      # Query active message offsets.
      ACTIVE_OFFSETS = 8
      # Query current transaction status.
      TRANSACTION_STATUS = 9
      # Client-initiated stream close.
      CLOSE_BY_CLIENT = 10
      # Server-initiated stream close.
      CLOSE_BY_SERVER = 11
    end

    # Configuration for polling messages from a queue channel.
    #
    # Pass to {QueuesClient#poll} or {DownstreamReceiver#poll} to receive
    # messages from a queue with transactional acknowledgement support.
    #
    # @example Poll for up to 10 messages with 5-second wait
    #   request = KubeMQ::Queues::QueuePollRequest.new(
    #     channel: "tasks.process",
    #     max_items: 10,
    #     wait_timeout: 5
    #   )
    #   response = client.poll(request)
    #
    # @see QueuesClient#poll
    # @see DownstreamReceiver#poll
    # @see QueuePollResponse
    class QueuePollRequest
      # @!attribute [rw] channel
      #   @return [String] queue channel to poll from
      # @!attribute [rw] max_items
      #   @return [Integer] maximum number of messages to receive (default: +1+)
      # @!attribute [rw] wait_timeout
      #   @return [Integer] how long to wait for messages before returning
      #   @note Timeout is in seconds
      # @!attribute [rw] auto_ack
      #   @return [Boolean] automatically acknowledge messages on receipt (default: +false+)
      attr_accessor :channel, :max_items, :wait_timeout, :auto_ack

      # @param channel [String] queue channel to poll from (required)
      # @param max_items [Integer] max messages to receive (default: +1+)
      # @param wait_timeout [Integer] wait timeout in seconds (default: +1+)
      # @param auto_ack [Boolean] auto-acknowledge on receipt (default: +false+)
      # @note +wait_timeout+ is in seconds
      def initialize(channel:, max_items: 1, wait_timeout: 1, auto_ack: false)
        @channel = channel
        @max_items = max_items
        @wait_timeout = wait_timeout
        @auto_ack = auto_ack
      end
    end
  end
end
