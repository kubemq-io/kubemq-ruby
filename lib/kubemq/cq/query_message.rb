# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module CQ
    # Outbound query message for the request/reply (with data) pattern.
    #
    # Construct a +QueryMessage+ and pass it to {CQClient#send_query}.
    # The broker forwards the query to a subscriber and returns a
    # {QueryResponse} containing the response data. Optionally set
    # {#cache_key} and {#cache_ttl} for server-side response caching.
    #
    # @example
    #   query = KubeMQ::CQ::QueryMessage.new(
    #     channel: "queries.user.get",
    #     timeout: 10_000,
    #     metadata: "get-user",
    #     body: '{"user_id": 42}',
    #     cache_key: "user:42",
    #     cache_ttl: 60
    #   )
    #   response = client.send_query(query)
    #   puts "Result: #{response.body}, cached: #{response.cache_hit}"
    #
    # @see CQClient#send_query
    # @see QueryResponse
    class QueryMessage
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
      # @!attribute [rw] timeout
      #   @return [Integer] maximum time to wait for a response
      #   @note Timeout is in milliseconds
      # @!attribute [rw] cache_key
      #   @return [String, nil] cache key for server-side response caching
      # @!attribute [rw] cache_ttl
      #   @return [Integer, nil] cache TTL in seconds
      attr_accessor :id, :channel, :metadata, :body, :tags, :timeout, :cache_key, :cache_ttl

      # @param channel [String] target channel name (required)
      # @param timeout [Integer] response timeout in milliseconds (required)
      # @param metadata [String, nil] arbitrary metadata
      # @param body [String, nil] message payload
      # @param tags [Hash{String => String}, nil] key-value tags (default: +{}+)
      # @param id [String, nil] message ID (default: auto-generated UUID)
      # @param cache_key [String, nil] server-side cache key
      # @param cache_ttl [Integer, nil] cache TTL in seconds
      # @note +timeout+ is in milliseconds
      def initialize(channel:, timeout:, metadata: nil, body: nil, tags: nil, id: nil,
                     cache_key: nil, cache_ttl: nil)
        @id = id || SecureRandom.uuid
        @channel = channel
        @timeout = timeout
        @metadata = metadata
        @body = body
        @tags = tags || {}
        @cache_key = cache_key
        @cache_ttl = cache_ttl
      end
    end
  end
end
