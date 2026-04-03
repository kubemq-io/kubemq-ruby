# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module CQ
    # Outbound command message for the request/reply (fire-and-confirm) pattern.
    #
    # Construct a +CommandMessage+ and pass it to {CQClient#send_command}.
    # The broker forwards the command to a subscriber and returns a
    # {CommandResponse} indicating whether it was executed.
    #
    # @example
    #   cmd = KubeMQ::CQ::CommandMessage.new(
    #     channel: "commands.user.create",
    #     timeout: 5000,
    #     metadata: "create-user",
    #     body: '{"name": "Alice"}',
    #     tags: { "source" => "api" }
    #   )
    #   response = client.send_command(cmd)
    #   puts "Executed: #{response.executed}"
    #
    # @see CQClient#send_command
    # @see CommandResponse
    class CommandMessage
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
      attr_accessor :id, :channel, :metadata, :body, :tags, :timeout

      # @param channel [String] target channel name (required)
      # @param timeout [Integer] response timeout in milliseconds (required)
      # @param metadata [String, nil] arbitrary metadata
      # @param body [String, nil] message payload
      # @param tags [Hash{String => String}, nil] key-value tags (default: +{}+)
      # @param id [String, nil] message ID (default: auto-generated UUID)
      # @note +timeout+ is in milliseconds
      def initialize(channel:, timeout:, metadata: nil, body: nil, tags: nil, id: nil)
        @id = id || SecureRandom.uuid
        @channel = channel
        @timeout = timeout
        @metadata = metadata
        @body = body
        @tags = tags || {}
      end
    end
  end
end
