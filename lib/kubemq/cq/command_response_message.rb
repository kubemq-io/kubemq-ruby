# frozen_string_literal: true

module KubeMQ
  module CQ
    # Outbound response to a received command, sent via {CQClient#send_response}.
    #
    # Construct from the fields of a {CommandReceived} — copy +id+ to
    # +request_id+ and +reply_channel+ — then set {#executed} and
    # optionally {#error}.
    #
    # @example Respond to a command
    #   response_msg = KubeMQ::CQ::CommandResponseMessage.new(
    #     request_id: received_cmd.id,
    #     reply_channel: received_cmd.reply_channel,
    #     executed: true
    #   )
    #   client.send_response(response_msg)
    #
    # @see CQClient#send_response
    # @see CommandReceived
    class CommandResponseMessage
      # @!attribute [rw] request_id
      #   @return [String] the original command's request identifier
      # @!attribute [rw] reply_channel
      #   @return [String] the channel to send the response on
      # @!attribute [rw] client_id
      #   @return [String, nil] responder's client identifier
      # @!attribute [rw] executed
      #   @return [Boolean] whether the command was executed successfully
      # @!attribute [rw] error
      #   @return [String, nil] error description if execution failed
      # @!attribute [rw] metadata
      #   @return [String, nil] response metadata
      # @!attribute [rw] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      attr_accessor :request_id, :reply_channel, :client_id, :executed,
                    :error, :metadata, :tags

      # @param request_id [String] the original command's request ID (required)
      # @param reply_channel [String] response channel from {CommandReceived#reply_channel} (required)
      # @param executed [Boolean] whether the command was executed (required)
      # @param error [String, nil] error description on failure
      # @param metadata [String, nil] response metadata
      # @param tags [Hash{String => String}, nil] key-value tags
      # @param client_id [String, nil] responder's client ID
      def initialize(request_id:, reply_channel:, executed:, error: nil, metadata: nil, tags: nil,
                     client_id: nil)
        @request_id = request_id
        @reply_channel = reply_channel
        @executed = executed
        @error = error
        @metadata = metadata
        @tags = tags || {}
        @client_id = client_id
      end
    end
  end
end
