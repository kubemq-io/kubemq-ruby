# frozen_string_literal: true

module KubeMQ
  module CQ
    # Outbound response to a received query, sent via {CQClient#send_response}.
    #
    # Construct from the fields of a {QueryReceived} — copy +id+ to
    # +request_id+ and +reply_channel+ — then set {#executed}, {#body},
    # and optionally {#cache_hit}.
    #
    # @example Respond to a query
    #   response_msg = KubeMQ::CQ::QueryResponseMessage.new(
    #     request_id: received_query.id,
    #     reply_channel: received_query.reply_channel,
    #     executed: true,
    #     body: '{"name": "Alice", "age": 30}'
    #   )
    #   client.send_response(response_msg)
    #
    # @see CQClient#send_response
    # @see QueryReceived
    class QueryResponseMessage
      # @!attribute [rw] request_id
      #   @return [String] the original query's request identifier
      # @!attribute [rw] reply_channel
      #   @return [String] the channel to send the response on
      # @!attribute [rw] client_id
      #   @return [String, nil] responder's client identifier
      # @!attribute [rw] executed
      #   @return [Boolean] whether the query was executed successfully
      # @!attribute [rw] error
      #   @return [String, nil] error description if execution failed
      # @!attribute [rw] body
      #   @return [String, nil] response payload
      # @!attribute [rw] metadata
      #   @return [String, nil] response metadata
      # @!attribute [rw] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      # @!attribute [rw] cache_hit
      #   @return [Boolean] whether this response should be cached
      attr_accessor :request_id, :reply_channel, :client_id, :executed,
                    :error, :body, :metadata, :tags, :cache_hit

      # @param request_id [String] the original query's request ID (required)
      # @param reply_channel [String] response channel from {QueryReceived#reply_channel} (required)
      # @param executed [Boolean] whether the query was executed (required)
      # @param error [String, nil] error description on failure
      # @param body [String, nil] response payload
      # @param metadata [String, nil] response metadata
      # @param tags [Hash{String => String}, nil] key-value tags
      # @param client_id [String, nil] responder's client ID
      # @param cache_hit [Boolean] whether this response is from cache (default: +false+)
      def initialize(request_id:, reply_channel:, executed:, error: nil, body: nil,
                     metadata: nil, tags: nil, client_id: nil, cache_hit: false)
        @request_id = request_id
        @reply_channel = reply_channel
        @executed = executed
        @error = error
        @body = body
        @metadata = metadata
        @tags = tags || {}
        @client_id = client_id
        @cache_hit = cache_hit
      end
    end
  end
end
