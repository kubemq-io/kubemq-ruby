# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module PubSub
    # Outbound event message for fire-and-forget pub/sub.
    #
    # Construct an +EventMessage+ and pass it to {PubSubClient#send_event}
    # or {PubSub::EventSender#publish}. Events are not persisted — use
    # {EventStoreMessage} for durable delivery.
    #
    # @example
    #   msg = KubeMQ::PubSub::EventMessage.new(
    #     channel: "notifications.email",
    #     metadata: "user-signup",
    #     body: '{"user_id": 42}',
    #     tags: { "priority" => "high" }
    #   )
    #   result = client.send_event(msg)
    #
    # @see PubSubClient#send_event
    # @see EventSender#publish
    # @see EventStoreMessage
    class EventMessage
      # @!attribute [rw] id
      #   @return [String] unique message identifier (auto-generated UUID if not provided)
      # @!attribute [rw] channel
      #   @return [String] target channel name
      # @!attribute [rw] metadata
      #   @return [String, nil] arbitrary metadata string
      # @!attribute [rw] body
      #   @return [String, nil] message payload (binary-safe)
      # @!attribute [rw] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      attr_accessor :id, :channel, :metadata, :body, :tags

      # @param channel [String] target channel name (required)
      # @param metadata [String, nil] arbitrary metadata
      # @param body [String, nil] message payload
      # @param tags [Hash{String => String}, nil] key-value tags (default: +{}+)
      # @param id [String, nil] message ID (default: auto-generated UUID)
      def initialize(channel:, metadata: nil, body: nil, tags: nil, id: nil)
        @id = id || SecureRandom.uuid
        @channel = channel
        @metadata = metadata
        @body = body
        @tags = tags || {}
      end
    end
  end
end
