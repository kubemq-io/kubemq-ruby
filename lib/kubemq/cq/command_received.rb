# frozen_string_literal: true

module KubeMQ
  module CQ
    # A command received by a subscriber via {CQClient#subscribe_to_commands}.
    #
    # After processing, use the {#reply_channel} and {#id} to construct a
    # {CommandResponseMessage} and send it back via {CQClient#send_response}.
    #
    # @see CQClient#subscribe_to_commands
    # @see CommandResponseMessage
    # @see CQClient#send_response
    class CommandReceived
      # @!attribute [r] id
      #   @return [String] request identifier (use as +request_id+ in the response)
      # @!attribute [r] channel
      #   @return [String] the channel the command was sent to
      # @!attribute [r] metadata
      #   @return [String] command metadata
      # @!attribute [r] body
      #   @return [String] command payload (binary)
      # @!attribute [r] reply_channel
      #   @return [String] channel to send the response back on
      # @!attribute [r] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      # @!attribute [r] timeout
      #   @return [Integer] original timeout from the sender (milliseconds)
      # @!attribute [r] client_id
      #   @return [String, nil] the sender's client identifier
      attr_reader :id, :channel, :metadata, :body, :reply_channel, :tags, :timeout, :client_id

      # @param id [String] request identifier
      # @param channel [String] source channel name
      # @param metadata [String] command metadata
      # @param body [String] command payload
      # @param reply_channel [String] response channel
      # @param tags [Hash{String => String}, nil] key-value tags
      # @param timeout [Integer] sender timeout in milliseconds (default: +0+)
      # @param client_id [String, nil] sender's client ID
      def initialize(id:, channel:, metadata:, body:, reply_channel:, tags:, timeout: 0, client_id: nil, **_)
        @id = id
        @channel = channel
        @metadata = metadata
        @body = body
        @reply_channel = reply_channel
        @tags = tags || {}
        @timeout = timeout
        @client_id = client_id
      end
    end
  end
end
