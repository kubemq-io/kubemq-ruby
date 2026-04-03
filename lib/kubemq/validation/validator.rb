# frozen_string_literal: true

module KubeMQ
  # Input validation helpers used by client methods before sending requests.
  #
  # All methods raise {ValidationError} on invalid input with an actionable
  # +suggestion+ field. Called internally -- not typically used in application code.
  #
  # @api private
  #
  # @see ValidationError
  # @see BaseClient
  # rubocop:disable Metrics/ModuleLength -- validation helpers per message type
  module Validator
    # Permitted characters for channel names (alphanumeric, dots, hyphens,
    # underscores, slashes, and wildcard tokens).
    CHANNEL_NAME_REGEX = %r{\A[a-zA-Z0-9._\-/>*]+\z}

    module_function

    # Validates a channel name for format and optional wildcard support.
    #
    # @param channel [String] the channel name to validate
    # @param allow_wildcards [Boolean] whether +*+ and +>+ are permitted
    # @return [void]
    # @raise [ValidationError] if the channel is nil, empty, contains invalid
    #   characters, ends with a dot, or uses wildcards when disallowed
    def validate_channel!(channel, allow_wildcards: false)
      if channel.nil? || channel.to_s.strip.empty?
        raise ValidationError.new('Channel name is required',
                                  suggestion: 'Provide a non-empty channel name.')
      end

      channel = channel.to_s

      unless channel.match?(CHANNEL_NAME_REGEX)
        raise ValidationError.new(
          "Channel name contains invalid characters: #{channel}",
          suggestion: 'Use only alphanumeric characters, dots, hyphens, underscores, and slashes.'
        )
      end

      if channel.end_with?('.')
        raise ValidationError.new("Channel name must not end with a dot: #{channel}",
                                  suggestion: 'Remove the trailing dot from the channel name.')
      end

      return if allow_wildcards

      return unless channel.include?('*') || channel.include?('>')

      raise ValidationError.new(
        "Wildcards are not allowed for this channel: #{channel}",
        suggestion: 'Use an exact channel name without wildcard characters.'
      )
    end

    # Validates that at least one of metadata or body is non-empty.
    #
    # @param metadata [String, nil] message metadata
    # @param body [String, nil] message body
    # @return [void]
    # @raise [ValidationError] if both metadata and body are nil or empty
    def validate_content!(metadata, body)
      metadata_empty = metadata.nil? || (metadata.is_a?(String) && metadata.empty?)
      body_empty = body.nil? || (body.is_a?(String) && body.empty?)
      return unless metadata_empty && body_empty

      raise ValidationError.new('Message must have non-empty metadata or body',
                                suggestion: 'Provide either metadata or body content.')
    end

    # Validates that a client ID is present and non-empty.
    #
    # @param client_id [String, nil] the client identifier to validate
    # @return [void]
    # @raise [ValidationError] if the client ID is nil or blank
    def validate_client_id!(client_id)
      return unless client_id.nil? || client_id.to_s.strip.empty?

      raise ValidationError.new('Client ID is required',
                                suggestion: 'Provide a non-empty client ID.')
    end

    # Validates that a timeout value is a positive number.
    #
    # @param timeout [Numeric] the timeout value to validate (in milliseconds
    #   for commands/queries)
    # @return [void]
    # @raise [ValidationError] if the timeout is not a positive number
    def validate_timeout!(timeout)
      return if timeout.is_a?(Numeric) && timeout.positive?

      raise ValidationError.new("Timeout must be greater than 0, got: #{timeout.inspect}",
                                suggestion: 'Provide a positive timeout value in milliseconds.')
    end

    # Validates cache parameters for query messages.
    #
    # @param cache_key [String, nil] the cache key (validation only applies when set)
    # @param cache_ttl [Numeric, nil] the cache TTL in seconds
    # @return [void]
    # @raise [ValidationError] if +cache_key+ is set but +cache_ttl+ is not positive
    def validate_cache!(cache_key, cache_ttl)
      return if cache_key.nil? || cache_key.empty?
      return if cache_ttl.is_a?(Numeric) && cache_ttl.positive?

      raise ValidationError.new('cache_ttl must be > 0 when cache_key is set',
                                suggestion: 'Provide a positive cache_ttl value in seconds.')
    end

    # Validates that a command/query response has required fields.
    #
    # @param request_id [String, nil] the originating request ID
    # @param reply_channel [String, nil] the reply channel from the request
    # @return [void]
    # @raise [ValidationError] if +request_id+ or +reply_channel+ is nil or blank
    def validate_response!(request_id, reply_channel)
      if request_id.nil? || request_id.to_s.strip.empty?
        raise ValidationError.new('request_id is required for response',
                                  suggestion: 'Use the request_id from the received request.')
      end

      return unless reply_channel.nil? || reply_channel.to_s.strip.empty?

      raise ValidationError.new('reply_channel is required for response',
                                suggestion: 'Use the reply_channel from the received request.')
    end

    # Validates events store subscription start position and its associated value.
    #
    # @param start_position [Integer, nil] one of the EventStoreStartPosition constants
    # @param start_position_value [Numeric, nil] sequence number, Unix timestamp,
    #   or delta seconds depending on the start position type
    # @return [void]
    # @raise [ValidationError] if the start position is missing or the value is
    #   invalid for the chosen position type
    def validate_events_store_subscription!(start_position, start_position_value)
      if start_position.nil? || start_position.zero?
        raise ValidationError.new(
          'Events Store subscription requires a start position',
          suggestion: 'Set start_position to one of: StartNewOnly(1), StartFromFirst(2), ' \
                      'StartFromLast(3), StartAtSequence(4), StartAtTime(5), StartAtTimeDelta(6).'
        )
      end

      case start_position
      when 4 # StartAtSequence
        unless start_position_value.is_a?(Numeric) && start_position_value.positive?
          raise ValidationError.new(
            "StartAtSequence requires a positive sequence value, got: #{start_position_value.inspect}",
            suggestion: 'Provide a positive sequence number.'
          )
        end
      when 5 # StartAtTime
        unless start_position_value.is_a?(Numeric) && start_position_value.positive?
          raise ValidationError.new(
            "StartAtTime requires a positive Unix timestamp, got: #{start_position_value.inspect}",
            suggestion: 'Provide a Unix timestamp in nanoseconds.'
          )
        end
      when 6 # StartAtTimeDelta
        unless start_position_value.is_a?(Numeric) && start_position_value.positive?
          raise ValidationError.new(
            "StartAtTimeDelta requires a positive delta in seconds, got: #{start_position_value.inspect}",
            suggestion: 'Provide a positive number of seconds to look back.'
          )
        end
      end
    end

    # Validates queue poll request parameters.
    #
    # @param max_items [Integer] maximum number of messages to poll (must be >= 1)
    # @param wait_timeout [Numeric] wait timeout in seconds (0..3600)
    # @return [void]
    # @raise [ValidationError] if +max_items+ < 1 or +wait_timeout+ is out of range
    def validate_queue_poll!(max_items, wait_timeout)
      if !max_items.is_a?(Integer) || max_items < 1
        raise ValidationError.new("max_items must be >= 1, got: #{max_items.inspect}",
                                  suggestion: 'Provide a positive integer for max_items.')
      end

      return if wait_timeout.is_a?(Numeric) && wait_timeout >= 0 && wait_timeout <= 3600

      raise ValidationError.new(
        "wait_timeout must be between 0 and 3600 seconds, got: #{wait_timeout.inspect}",
        suggestion: 'Provide a wait_timeout between 0 and 3600 seconds.'
      )
    end

    # Validates queue receive request parameters (simple API).
    #
    # @param max_messages [Integer] maximum messages to receive (1..1024)
    # @param wait_timeout_seconds [Numeric] wait timeout in seconds (0..3600)
    # @return [void]
    # @raise [ValidationError] if +max_messages+ is out of range or
    #   +wait_timeout_seconds+ is out of range
    def validate_queue_receive!(max_messages, wait_timeout_seconds)
      if !max_messages.is_a?(Integer) || max_messages < 1 || max_messages > 1024
        raise ValidationError.new(
          "max_messages must be between 1 and 1024, got: #{max_messages.inspect}",
          suggestion: 'Provide max_messages between 1 and 1024.'
        )
      end

      return if wait_timeout_seconds.is_a?(Numeric) && wait_timeout_seconds >= 0 && wait_timeout_seconds <= 3600

      raise ValidationError.new(
        "wait_timeout_seconds must be between 0 and 3600, got: #{wait_timeout_seconds.inspect}",
        suggestion: 'Provide wait_timeout_seconds between 0 and 3600.'
      )
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
