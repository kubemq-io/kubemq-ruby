# frozen_string_literal: true

module KubeMQ
  module CQ
    # Response returned by {CQClient#send_query} after a subscriber
    # processes the query.
    #
    # Contains the response {#body} and {#metadata}, plus a {#cache_hit}
    # flag indicating whether the response was served from the broker's
    # server-side cache.
    #
    # @see CQClient#send_query
    # @see QueryMessage
    class QueryResponse
      # @!attribute [r] client_id
      #   @return [String] the responder's client identifier
      # @!attribute [r] request_id
      #   @return [String] the original query request identifier
      # @!attribute [r] executed
      #   @return [Boolean] +true+ if the query was executed successfully
      # @!attribute [r] error
      #   @return [String, nil] error description if execution failed
      # @!attribute [r] timestamp
      #   @return [Integer] broker-assigned response timestamp (Unix nanoseconds)
      # @!attribute [r] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      # @!attribute [r] body
      #   @return [String, nil] response payload
      # @!attribute [r] metadata
      #   @return [String, nil] response metadata
      # @!attribute [r] cache_hit
      #   @return [Boolean] +true+ if the response was served from cache
      attr_reader :client_id, :request_id, :executed, :error, :timestamp,
                  :tags, :body, :metadata, :cache_hit

      # @param client_id [String] responder's client ID
      # @param request_id [String] original request ID
      # @param executed [Boolean] whether the query was executed
      # @param error [String, nil] error description on failure
      # @param timestamp [Integer] response timestamp (default: +0+)
      # @param tags [Hash{String => String}, nil] key-value tags
      # @param body [String, nil] response payload
      # @param metadata [String, nil] response metadata
      # @param cache_hit [Boolean] whether served from cache (default: +false+)
      def initialize(client_id:, request_id:, executed:, error: nil, timestamp: 0,
                     tags: nil, body: nil, metadata: nil, cache_hit: false)
        @client_id = client_id
        @request_id = request_id
        @executed = executed
        @error = error
        @timestamp = timestamp
        @tags = tags || {}
        @body = body
        @metadata = metadata
        @cache_hit = cache_hit
      end
    end
  end
end
