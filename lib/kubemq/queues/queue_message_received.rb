# frozen_string_literal: true

module KubeMQ
  module Queues
    # Server-assigned attributes attached to a received queue message.
    #
    # Contains delivery metadata such as receive count, routing history,
    # and timing information. Access via {QueueMessageReceived#attributes}.
    #
    # @see QueueMessageReceived
    class QueueMessageAttributes
      # @!attribute [r] timestamp
      #   @return [Integer] broker-assigned timestamp (Unix nanoseconds)
      # @!attribute [r] sequence
      #   @return [Integer] broker-assigned sequence number
      # @!attribute [r] md5_of_body
      #   @return [String] MD5 hash of the message body
      # @!attribute [r] receive_count
      #   @return [Integer] number of times this message has been delivered
      # @!attribute [r] re_routed
      #   @return [Boolean] whether this message was re-routed from another queue
      # @!attribute [r] re_routed_from_queue
      #   @return [String] original queue channel if re-routed
      # @!attribute [r] expiration_at
      #   @return [Integer] expiration timestamp (Unix nanoseconds); +0+ if no expiration
      # @!attribute [r] delayed_to
      #   @return [Integer] visibility delay timestamp (Unix nanoseconds); +0+ if no delay
      attr_reader :timestamp, :sequence, :md5_of_body, :receive_count,
                  :re_routed, :re_routed_from_queue, :expiration_at, :delayed_to

      # @param timestamp [Integer] broker timestamp (default: +0+)
      # @param sequence [Integer] broker sequence number (default: +0+)
      # @param md5_of_body [String] MD5 hash of body (default: +""+)
      # @param receive_count [Integer] delivery count (default: +0+)
      # @param re_routed [Boolean] whether re-routed (default: +false+)
      # @param re_routed_from_queue [String] original queue if re-routed (default: +""+)
      # @param expiration_at [Integer] expiration timestamp (default: +0+)
      # @param delayed_to [Integer] delay timestamp (default: +0+)
      def initialize(timestamp: 0, sequence: 0, md5_of_body: '', receive_count: 0,
                     re_routed: false, re_routed_from_queue: '', expiration_at: 0, delayed_to: 0)
        @timestamp = timestamp
        @sequence = sequence
        @md5_of_body = md5_of_body
        @receive_count = receive_count
        @re_routed = re_routed
        @re_routed_from_queue = re_routed_from_queue
        @expiration_at = expiration_at
        @delayed_to = delayed_to
      end
    end

    # A message received from a queue via {QueuesClient#poll} or
    # {QueuesClient#receive_queue_messages}.
    #
    # When received through the stream API ({QueuesClient#poll}),
    # transactional methods {#ack}, {#reject}, and {#requeue} are
    # available for per-message acknowledgement within the poll
    # transaction.
    #
    # @example Acknowledge a single message
    #   response = client.poll(request)
    #   response.messages.each do |msg|
    #     process(msg.body)
    #     msg.ack
    #   end
    #
    # @example Reject and requeue
    #   response.messages.each do |msg|
    #     if valid?(msg)
    #       msg.ack
    #     else
    #       msg.requeue(channel: "tasks.retry")
    #     end
    #   end
    #
    # @see QueuesClient#poll
    # @see QueuePollResponse
    # @see QueueMessageAttributes
    class QueueMessageReceived
      # @!attribute [r] id
      #   @return [String] message identifier
      # @!attribute [r] channel
      #   @return [String] source queue channel name
      # @!attribute [r] metadata
      #   @return [String] message metadata
      # @!attribute [r] body
      #   @return [String] message payload (binary)
      # @!attribute [r] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      # @!attribute [r] attributes
      #   @return [QueueMessageAttributes, nil] server-assigned delivery attributes
      attr_reader :id, :channel, :metadata, :body, :tags, :attributes

      # @param id [String] message identifier
      # @param channel [String] source channel name
      # @param metadata [String] message metadata
      # @param body [String] message payload
      # @param tags [Hash{String => String}, nil] key-value tags
      # @param attributes [QueueMessageAttributes, nil] server-assigned attributes
      # @param action_proc [Proc, nil] internal callback for transaction actions
      # @param sequence [Integer] message sequence for transaction operations
      # @api private
      def initialize(id:, channel:, metadata:, body:, tags:, attributes: nil,
                     action_proc: nil, sequence: 0)
        @id = id
        @channel = channel
        @metadata = metadata
        @body = body
        @tags = tags || {}
        @attributes = attributes
        @action_proc = action_proc
        @sequence = sequence
      end

      # Acknowledges this message within the poll transaction.
      #
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound (simple API)
      def ack
        raise TransactionError, 'No downstream receiver bound' unless @action_proc

        @action_proc.call(:AckRange, sequence_range: [@sequence])
      end

      # Rejects (negative-acknowledges) this message. The broker may
      # redeliver it to another consumer or move it to a dead-letter queue.
      #
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound
      def reject
        raise TransactionError, 'No downstream receiver bound' unless @action_proc

        @action_proc.call(:NAckRange, sequence_range: [@sequence])
      end

      # Requeues this message to a different channel.
      #
      # @param channel [String] destination channel name
      # @return [void]
      # @raise [TransactionError] if no downstream receiver is bound
      def requeue(channel:)
        raise TransactionError, 'No downstream receiver bound' unless @action_proc

        @action_proc.call(:ReQueueRange, channel: channel, sequence_range: [@sequence])
      end
    end
  end
end
