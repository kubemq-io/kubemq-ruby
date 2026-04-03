# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module Queues
    # Delivery policy for queue messages — expiration, delay, and dead-letter settings.
    #
    # Attach to a {QueueMessage} via the +policy+ attribute to control
    # when the message becomes visible, when it expires, and where it
    # goes after exceeding the maximum receive count.
    #
    # @example Dead-letter policy
    #   policy = KubeMQ::Queues::QueueMessagePolicy.new(
    #     max_receive_count: 3,
    #     max_receive_queue: "orders.dlq",
    #     expiration_seconds: 3600
    #   )
    #
    # @see QueueMessage
    class QueueMessagePolicy
      # @!attribute [rw] expiration_seconds
      #   @return [Integer] message TTL in seconds; +0+ means no expiration (default: +0+)
      # @!attribute [rw] delay_seconds
      #   @return [Integer] delay before the message becomes visible in seconds (default: +0+)
      # @!attribute [rw] max_receive_count
      #   @return [Integer] max delivery attempts before dead-lettering; +0+ means unlimited (default: +0+)
      # @!attribute [rw] max_receive_queue
      #   @return [String] dead-letter queue channel name (default: +""+)
      attr_accessor :expiration_seconds, :delay_seconds, :max_receive_count, :max_receive_queue

      # @param expiration_seconds [Integer] message TTL in seconds (default: +0+)
      # @param delay_seconds [Integer] visibility delay in seconds (default: +0+)
      # @param max_receive_count [Integer] max delivery attempts (default: +0+)
      # @param max_receive_queue [String] dead-letter queue channel (default: +""+)
      def initialize(expiration_seconds: 0, delay_seconds: 0, max_receive_count: 0, max_receive_queue: '')
        @expiration_seconds = expiration_seconds
        @delay_seconds = delay_seconds
        @max_receive_count = max_receive_count
        @max_receive_queue = max_receive_queue
      end
    end

    # Outbound queue message for point-to-point messaging.
    #
    # Construct a +QueueMessage+ and send it via {QueuesClient#send_queue_message},
    # {QueuesClient#send_queue_message_stream}, or {UpstreamSender#publish}.
    # Optionally attach a {QueueMessagePolicy} for expiration, delay, and
    # dead-letter handling.
    #
    # @example Send a queue message with policy
    #   msg = KubeMQ::Queues::QueueMessage.new(
    #     channel: "tasks.process",
    #     body: '{"task_id": 1}',
    #     metadata: "task",
    #     tags: { "priority" => "high" },
    #     policy: KubeMQ::Queues::QueueMessagePolicy.new(
    #       expiration_seconds: 300,
    #       max_receive_count: 3,
    #       max_receive_queue: "tasks.dlq"
    #     )
    #   )
    #   result = client.send_queue_message(msg)
    #
    # @see QueuesClient#send_queue_message
    # @see UpstreamSender#publish
    # @see QueueMessagePolicy
    class QueueMessage
      # @!attribute [rw] id
      #   @return [String] unique message identifier (auto-generated UUID if not provided)
      # @!attribute [rw] channel
      #   @return [String] target queue channel name
      # @!attribute [rw] metadata
      #   @return [String, nil] arbitrary metadata string
      # @!attribute [rw] body
      #   @return [String, nil] message payload (binary-safe)
      # @!attribute [rw] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      # @!attribute [rw] policy
      #   @return [QueueMessagePolicy, nil] delivery policy (expiration, delay, dead-letter)
      attr_accessor :id, :channel, :metadata, :body, :tags, :policy

      # @param channel [String] target queue channel name (required)
      # @param metadata [String, nil] arbitrary metadata
      # @param body [String, nil] message payload
      # @param tags [Hash{String => String}, nil] key-value tags (default: +{}+)
      # @param id [String, nil] message ID (default: auto-generated UUID)
      # @param policy [QueueMessagePolicy, nil] delivery policy (default: +nil+)
      def initialize(channel:, metadata: nil, body: nil, tags: nil, id: nil, policy: nil)
        @id = id || SecureRandom.uuid
        @channel = channel
        @metadata = metadata
        @body = body
        @tags = tags || {}
        @policy = policy
      end
    end
  end
end
