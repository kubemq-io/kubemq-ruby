# frozen_string_literal: true

module KubeMQ
  # Base exception class for all KubeMQ SDK errors.
  #
  # Provides structured error context including an error code, retryable flag,
  # originating operation, channel name, and an actionable suggestion.
  # Rescue +KubeMQ::Error+ for generic handling or specific subclasses for
  # targeted recovery logic.
  #
  # @example Generic error handling
  #   begin
  #     client.send_event(msg)
  #   rescue KubeMQ::TimeoutError => e
  #     retry if e.retryable?
  #   rescue KubeMQ::ValidationError => e
  #     logger.warn("Invalid input: #{e.message} — #{e.suggestion}")
  #   rescue KubeMQ::Error => e
  #     logger.error("#{e.class}: #{e.message} (code=#{e.code})")
  #   end
  #
  # @see ErrorCode
  # @see ErrorMapper
  class Error < StandardError
    # @!attribute [r] code
    #   @return [String, nil] SDK error code from {ErrorCode} constants
    # @!attribute [r] details
    #   @return [Hash] additional error context details
    # @!attribute [r] operation
    #   @return [String] the operation that failed (e.g., +"send_event"+)
    # @!attribute [r] channel
    #   @return [String, nil] the channel name involved, if applicable
    # @!attribute [r] request_id
    #   @return [String] the request ID involved, if applicable
    # @!attribute [r] suggestion
    #   @return [String, nil] actionable suggestion for resolving the error
    attr_reader :code, :details, :operation, :channel, :request_id, :suggestion

    # Creates a new KubeMQ error.
    #
    # @param message [String] human-readable error description
    # @param code [String, nil] error code from {ErrorCode}
    # @param details [Hash, nil] additional context (default: +{}+)
    # @param cause [Exception, nil] original exception that triggered this error
    # @param operation [String] the SDK operation that failed (default: +""+)
    # @param channel [String, nil] the channel name involved
    # @param request_id [String] request ID for correlation (default: +""+)
    # @param suggestion [String, nil] actionable suggestion for resolution
    # @param retryable [Boolean] whether the operation may succeed on retry (default: +false+)
    def initialize(message, code: nil, details: nil, cause: nil, operation: '', channel: nil,
                   request_id: '', suggestion: nil, retryable: false)
      super(message)
      @error_message = message
      @code = code
      @details = details || {}
      @original_error = cause
      @operation = operation
      @channel = channel
      @request_id = request_id
      @suggestion = suggestion
      @retryable = retryable
    end

    # Returns the original exception that caused this error.
    #
    # @return [Exception, nil] the underlying cause
    def cause
      @original_error || super
    end

    # Returns whether this error is transient and the operation may succeed on retry.
    #
    # @return [Boolean]
    def retryable?
      @retryable
    end

    # Formats the error as a human-readable string including operation,
    # channel, and suggestion when available.
    #
    # @return [String] formatted error message
    def to_s
      parts = []
      parts << if !@operation.to_s.empty? && @channel
                 "#{@operation} failed on channel \"#{@channel}\": #{@error_message}"
               elsif !@operation.to_s.empty?
                 "#{@operation} failed: #{@error_message}"
               else
                 @error_message
               end
      parts << "  Suggestion: #{@suggestion}" if @suggestion
      parts.join("\n")
    end
  end

  # Raised when the gRPC connection to the broker fails or is lost.
  #
  # Covers DNS resolution failures, TCP connection refused, and network
  # interruptions. Retryable by default — the reconnect policy will
  # attempt recovery automatically.
  #
  # @see ReconnectPolicy
  class ConnectionError < Error
  end

  # Raised when authentication or authorization fails.
  #
  # Covers invalid, expired, or missing auth tokens (+AUTH_FAILED+) and
  # insufficient permissions (+PERMISSION_DENIED+). Not retryable — fix
  # credentials before retrying.
  #
  # @example
  #   begin
  #     client.ping
  #   rescue KubeMQ::AuthenticationError => e
  #     logger.error("Auth failed: #{e.message}")
  #   end
  class AuthenticationError < ConnectionError
    def initialize(message, **kwargs)
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end

  # Raised when an operation exceeds its deadline.
  #
  # Retryable by default. Increase the timeout or investigate broker load
  # if this error persists.
  #
  # @note Default error code is +CONNECTION_TIMEOUT+.
  class TimeoutError < Error
    def initialize(message, **kwargs)
      kwargs[:retryable] = true unless kwargs.key?(:retryable)
      kwargs[:code] ||= ErrorCode::CONNECTION_TIMEOUT
      super
    end
  end

  # Raised when request parameters fail validation.
  #
  # Covers invalid channel names, empty messages, out-of-range values, and
  # duplicate resources. Not retryable — fix the input before retrying.
  class ValidationError < Error
    def initialize(message, **kwargs)
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end

  # Raised when the client configuration is invalid.
  #
  # Covers missing or malformed address, invalid TLS paths, and conflicting
  # options. Not retryable — fix the configuration before creating a new client.
  #
  # @see Configuration
  class ConfigurationError < Error
    def initialize(message, **kwargs)
      kwargs[:code] ||= ErrorCode::CONFIGURATION_ERROR
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end

  # Raised when a channel operation fails at the broker.
  #
  # Covers channel-not-found, creation failures, and deletion conflicts.
  class ChannelError < Error
  end

  # Raised when a message operation fails.
  #
  # Covers send failures, resource exhaustion (rate limiting), and
  # message-level broker rejections.
  class MessageError < Error
  end

  # Raised when a queue transaction action fails.
  #
  # Covers ack, reject, and requeue failures on queue messages, as well
  # as aborted operations due to transaction conflicts.
  #
  # @see Queues::QueueMessageReceived#ack
  # @see Queues::QueueMessageReceived#reject
  # @see Queues::QueueMessageReceived#requeue
  class TransactionError < Error
  end

  # Raised when an operation is attempted on a closed client.
  #
  # Not retryable — create a new client instance to continue operations.
  #
  # @see BaseClient#close
  class ClientClosedError < Error
    def initialize(message = 'Client is closed', **kwargs)
      kwargs[:code] ||= ErrorCode::CLIENT_CLOSED
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end

  # Raised when an operation is attempted before the connection is established.
  #
  # The transport exists but has not reached the READY state. Retryable —
  # wait for the reconnect policy to establish the connection.
  #
  # @see ReconnectPolicy
  class ConnectionNotReadyError < Error
    def initialize(message = 'Connection is not ready', **kwargs)
      kwargs[:code] ||= ErrorCode::CONNECTION_NOT_READY
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end

  # Raised when a gRPC bidirectional stream breaks unexpectedly.
  #
  # For queue upstream/downstream streams, the +unacked_message_ids+ field
  # lists messages that may not have been acknowledged before the break.
  # Subscription streams auto-reconnect; sender/receiver streams must be
  # recreated manually.
  #
  # @note This error is retryable. Create a new sender or receiver after
  #   receiving this error.
  #
  # @see QueuesClient#create_upstream_sender
  # @see QueuesClient#create_downstream_receiver
  class StreamBrokenError < Error
    # @return [Array<String>] message IDs that were in-flight when the stream broke
    attr_reader :unacked_message_ids

    # @param message [String] error description
    # @param unacked_message_ids [Array<String>, nil] IDs of in-flight messages
    # @param kwargs [Hash] additional options forwarded to {Error#initialize}
    def initialize(message, unacked_message_ids: nil, **kwargs)
      kwargs[:code] ||= ErrorCode::STREAM_BROKEN
      kwargs[:retryable] = true unless kwargs.key?(:retryable)
      super(message, **kwargs)
      @unacked_message_ids = unacked_message_ids || []
    end
  end

  # Raised when the reconnect message buffer reaches capacity.
  #
  # During disconnection, outbound messages are buffered. When the buffer
  # is full, the oldest message is dropped. Not retryable — wait for the
  # connection to recover or increase the buffer size.
  #
  # @see Transport::MessageBuffer
  class BufferFullError < Error
    # @return [Integer] current buffer size when the error occurred
    attr_reader :buffer_size

    # @param message [String] error description
    # @param buffer_size [Integer] buffer size at time of overflow (default: +0+)
    # @param kwargs [Hash] additional options forwarded to {Error#initialize}
    def initialize(message, buffer_size: 0, **kwargs)
      kwargs[:code] = ErrorCode::BUFFER_FULL
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super(message, **kwargs)
      @buffer_size = buffer_size
    end
  end

  # Raised when an operation is cooperatively cancelled via {CancellationToken}.
  #
  # Not retryable — cancellation is intentional.
  #
  # @see CancellationToken
  class CancellationError < Error
    def initialize(message = 'Operation cancelled', **kwargs)
      kwargs[:code] = ErrorCode::CANCELLED
      kwargs[:retryable] = false unless kwargs.key?(:retryable)
      super
    end
  end
end
