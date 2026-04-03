# frozen_string_literal: true

module KubeMQ
  module PubSub
    # A durable event received from an events store subscription.
    #
    # Delivered to the block passed to {PubSubClient#subscribe_to_events_store}.
    # The {#sequence} value can be used to track replay position.
    #
    # @see PubSubClient#subscribe_to_events_store
    # @see EventsStoreSubscription
    class EventStoreReceived
      # @!attribute [r] id
      #   @return [String] unique event identifier
      # @!attribute [r] channel
      #   @return [String] the channel the event was published to
      # @!attribute [r] metadata
      #   @return [String] event metadata
      # @!attribute [r] body
      #   @return [String] event payload (binary)
      # @!attribute [r] timestamp
      #   @return [Integer] broker-assigned timestamp (Unix nanoseconds)
      # @!attribute [r] sequence
      #   @return [Integer] broker-assigned sequence number for replay tracking
      # @!attribute [r] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      attr_reader :id, :channel, :metadata, :body, :timestamp, :sequence, :tags

      # @param id [String] event identifier
      # @param channel [String] source channel name
      # @param metadata [String] event metadata
      # @param body [String] event payload
      # @param timestamp [Integer] broker timestamp (Unix nanoseconds)
      # @param sequence [Integer] broker sequence number
      # @param tags [Hash{String => String}, nil] key-value tags
      def initialize(id:, channel:, metadata:, body:, timestamp:, sequence:, tags:)
        @id = id
        @channel = channel
        @metadata = metadata
        @body = body
        @timestamp = timestamp
        @sequence = sequence
        @tags = tags || {}
      end
    end
  end
end
