# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module PubSub
    # Outbound durable event message for the events store pattern.
    #
    # Unlike {EventMessage}, events store messages are persisted by the
    # broker and can be replayed by subscribers using start-position
    # policies. Pass to {PubSubClient#send_event_store} or
    # {PubSub::EventStoreSender#publish}.
    #
    # @example
    #   msg = KubeMQ::PubSub::EventStoreMessage.new(
    #     channel: "orders.created",
    #     metadata: "order-event",
    #     body: '{"order_id": 100}',
    #     tags: { "region" => "us-east" }
    #   )
    #   result = client.send_event_store(msg)
    #
    # @see PubSubClient#send_event_store
    # @see EventStoreSender#publish
    # @see EventMessage
    class EventStoreMessage
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
