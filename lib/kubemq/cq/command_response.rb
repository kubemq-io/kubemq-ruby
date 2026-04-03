# frozen_string_literal: true

module KubeMQ
  module CQ
    # Response returned by {CQClient#send_command} after a subscriber
    # processes the command.
    #
    # Check {#executed} to confirm the command was handled successfully.
    # If +executed+ is +false+, inspect {#error} for the reason.
    #
    # @see CQClient#send_command
    # @see CommandMessage
    class CommandResponse
      # @!attribute [r] client_id
      #   @return [String] the responder's client identifier
      # @!attribute [r] request_id
      #   @return [String] the original command request identifier
      # @!attribute [r] executed
      #   @return [Boolean] +true+ if the command was executed successfully
      # @!attribute [r] error
      #   @return [String, nil] error description if execution failed
      # @!attribute [r] timestamp
      #   @return [Integer] broker-assigned response timestamp (Unix nanoseconds)
      # @!attribute [r] tags
      #   @return [Hash{String => String}] user-defined key-value tags
      attr_reader :client_id, :request_id, :executed, :error, :timestamp, :tags

      # @param client_id [String] responder's client ID
      # @param request_id [String] original request ID
      # @param executed [Boolean] whether the command was executed
      # @param error [String, nil] error description on failure
      # @param timestamp [Integer] response timestamp (default: +0+)
      # @param tags [Hash{String => String}, nil] key-value tags
      def initialize(client_id:, request_id:, executed:, error: nil, timestamp: 0, tags: nil)
        @client_id = client_id
        @request_id = request_id
        @executed = executed
        @error = error
        @timestamp = timestamp
        @tags = tags || {}
      end
    end
  end
end
