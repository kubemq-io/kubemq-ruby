# frozen_string_literal: true

module KubeMQ
  # Enumeration of SDK error codes used in {Error#code}.
  #
  # Each code maps to an {ErrorCategory} and retryable flag via {ERROR_CLASSIFICATION},
  # and to an actionable suggestion via {ERROR_SUGGESTIONS}.
  #
  # @see Error
  # @see ErrorCategory
  # @see ERROR_CLASSIFICATION
  module ErrorCode
    # gRPC connection timed out or deadline exceeded.
    CONNECTION_TIMEOUT = 'CONNECTION_TIMEOUT'
    # Broker is unreachable — network, DNS, or firewall issue.
    UNAVAILABLE = 'UNAVAILABLE'
    # Transport exists but is not in the READY state.
    CONNECTION_NOT_READY = 'CONNECTION_NOT_READY'
    # Authentication token is invalid, expired, or missing.
    AUTH_FAILED = 'AUTH_FAILED'
    # Authenticated but lacking required permissions.
    PERMISSION_DENIED = 'PERMISSION_DENIED'
    # Request parameters failed validation.
    VALIDATION_ERROR = 'VALIDATION_ERROR'
    # Resource (channel, queue) already exists.
    ALREADY_EXISTS = 'ALREADY_EXISTS'
    # Sequence number or offset is out of valid range.
    OUT_OF_RANGE = 'OUT_OF_RANGE'
    # Requested channel or resource does not exist.
    NOT_FOUND = 'NOT_FOUND'
    # Broker rate limit or resource quota exceeded.
    RESOURCE_EXHAUSTED = 'RESOURCE_EXHAUSTED'
    # Operation aborted due to a conflict (e.g., transaction contention).
    ABORTED = 'ABORTED'
    # Internal broker error — check server logs.
    INTERNAL = 'INTERNAL'
    # Unknown error — check server logs.
    UNKNOWN = 'UNKNOWN'
    # Operation not supported by the broker version.
    UNIMPLEMENTED = 'UNIMPLEMENTED'
    # Unrecoverable data loss at the broker.
    DATA_LOSS = 'DATA_LOSS'
    # Operation was cooperatively cancelled via {CancellationToken}.
    CANCELLED = 'CANCELLED'
    # Reconnect message buffer is full; oldest messages dropped.
    BUFFER_FULL = 'BUFFER_FULL'
    # A bidirectional gRPC stream broke unexpectedly.
    STREAM_BROKEN = 'STREAM_BROKEN'
    # Client has been closed; create a new instance.
    CLIENT_CLOSED = 'CLIENT_CLOSED'
    # Invalid client configuration (address, TLS, etc.).
    CONFIGURATION_ERROR = 'CONFIGURATION_ERROR'
    # A user-provided callback raised an exception.
    CALLBACK_ERROR = 'CALLBACK_ERROR'
  end

  # Categories for classifying {ErrorCode} values by failure domain.
  #
  # Used by {KubeMQ.classify_error} to determine error handling strategy.
  #
  # @see ERROR_CLASSIFICATION
  # @see KubeMQ.classify_error
  module ErrorCategory
    # Temporary failure that may resolve on retry (e.g., network blip).
    TRANSIENT = 'TRANSIENT'
    # Operation exceeded its deadline.
    TIMEOUT = 'TIMEOUT'
    # Rate limit or resource quota exceeded.
    THROTTLING = 'THROTTLING'
    # Invalid or missing authentication credentials.
    AUTHENTICATION = 'AUTHENTICATION'
    # Valid credentials but insufficient permissions.
    AUTHORIZATION = 'AUTHORIZATION'
    # Invalid request parameters or preconditions not met.
    VALIDATION = 'VALIDATION'
    # Requested resource does not exist.
    NOT_FOUND = 'NOT_FOUND'
    # Unrecoverable error — requires operator intervention.
    FATAL = 'FATAL'
    # Operation was intentionally cancelled.
    CANCELLATION = 'CANCELLATION'
    # Client-side buffer overflow during disconnection.
    BACKPRESSURE = 'BACKPRESSURE'
    # Error in user-provided callback code.
    RUNTIME = 'RUNTIME'
  end

  # Maps each {ErrorCode} to its {ErrorCategory} and retryable flag.
  #
  # Each entry is +[category, retryable]+ where +category+ is an
  # {ErrorCategory} constant and +retryable+ is a Boolean.
  #
  # @return [Hash{String => Array(String, Boolean)}]
  #
  # @see ErrorCode
  # @see ErrorCategory
  ERROR_CLASSIFICATION = {
    ErrorCode::UNAVAILABLE => [ErrorCategory::TRANSIENT, true],
    ErrorCode::ABORTED => [ErrorCategory::TRANSIENT, true],
    ErrorCode::CONNECTION_TIMEOUT => [ErrorCategory::TIMEOUT, true],
    ErrorCode::RESOURCE_EXHAUSTED => [ErrorCategory::THROTTLING, true],
    ErrorCode::AUTH_FAILED => [ErrorCategory::AUTHENTICATION, false],
    ErrorCode::PERMISSION_DENIED => [ErrorCategory::AUTHORIZATION, false],
    ErrorCode::VALIDATION_ERROR => [ErrorCategory::VALIDATION, false],
    ErrorCode::ALREADY_EXISTS => [ErrorCategory::VALIDATION, false],
    ErrorCode::OUT_OF_RANGE => [ErrorCategory::VALIDATION, false],
    ErrorCode::NOT_FOUND => [ErrorCategory::NOT_FOUND, false],
    ErrorCode::INTERNAL => [ErrorCategory::FATAL, false],
    ErrorCode::UNKNOWN => [ErrorCategory::TRANSIENT, true],
    ErrorCode::UNIMPLEMENTED => [ErrorCategory::FATAL, false],
    ErrorCode::DATA_LOSS => [ErrorCategory::FATAL, false],
    ErrorCode::CANCELLED => [ErrorCategory::CANCELLATION, false],
    ErrorCode::BUFFER_FULL => [ErrorCategory::BACKPRESSURE, false],
    ErrorCode::STREAM_BROKEN => [ErrorCategory::TRANSIENT, true],
    ErrorCode::CLIENT_CLOSED => [ErrorCategory::FATAL, false],
    ErrorCode::CONNECTION_NOT_READY => [ErrorCategory::TRANSIENT, true],
    ErrorCode::CONFIGURATION_ERROR => [ErrorCategory::VALIDATION, false],
    ErrorCode::CALLBACK_ERROR => [ErrorCategory::RUNTIME, false]
  }.freeze

  # Maps each {ErrorCode} to a human-readable recovery suggestion.
  #
  # Used by {ErrorMapper} to populate {Error#suggestion} and by
  # {KubeMQ.suggestion_for} for programmatic lookup.
  #
  # @return [Hash{String => String}]
  #
  # @see Error#suggestion
  ERROR_SUGGESTIONS = {
    ErrorCode::UNAVAILABLE => 'Check server connectivity and firewall rules.',
    ErrorCode::AUTH_FAILED => 'Verify auth token is valid and not expired.',
    ErrorCode::PERMISSION_DENIED => 'Verify credentials have required permissions.',
    ErrorCode::NOT_FOUND => 'Verify channel/queue exists or create it first.',
    ErrorCode::VALIDATION_ERROR => 'Check request parameters.',
    ErrorCode::ALREADY_EXISTS => 'Resource already exists.',
    ErrorCode::CONNECTION_TIMEOUT => 'Increase timeout or check server load.',
    ErrorCode::RESOURCE_EXHAUSTED => 'Reduce send rate or increase server capacity.',
    ErrorCode::BUFFER_FULL => 'Wait for connection to recover or increase buffer_size.',
    ErrorCode::STREAM_BROKEN => 'Subscriptions will attempt to reconnect automatically. Stream senders must be recreated.',
    ErrorCode::CLIENT_CLOSED => 'The client has been closed. Create a new client instance.',
    ErrorCode::INTERNAL => 'Internal server error. Check server logs.',
    ErrorCode::UNKNOWN => 'An unknown error occurred. Check server logs.',
    ErrorCode::CONFIGURATION_ERROR => 'Check client configuration: address, TLS settings, credentials.',
    ErrorCode::CANCELLED => 'The operation was cancelled.',
    ErrorCode::UNIMPLEMENTED => 'Operation not supported. Check server version.',
    ErrorCode::DATA_LOSS => 'Unrecoverable data loss. Check server storage.',
    ErrorCode::OUT_OF_RANGE => 'Check pagination parameters or sequence numbers.',
    ErrorCode::ABORTED => 'Operation aborted due to conflict. Retry may succeed.',
    ErrorCode::CONNECTION_NOT_READY => 'Wait for the client to connect or check server availability.',
    ErrorCode::CALLBACK_ERROR => 'A user callback raised an exception. Fix the callback code.'
  }.freeze

  # Classifies an error by its {ErrorCode} into a category and retryable flag.
  #
  # @param error [Error] an error with a +code+ attribute
  #
  # @return [Array(String, Boolean)] +[category, retryable]+ from {ERROR_CLASSIFICATION};
  #   defaults to +[ErrorCategory::FATAL, false]+ for unknown codes
  #
  # @example
  #   category, retryable = KubeMQ.classify_error(error)
  #   retry if retryable
  def self.classify_error(error)
    return [ErrorCategory::FATAL, false] unless error.respond_to?(:code) && error.code

    ERROR_CLASSIFICATION.fetch(error.code, [ErrorCategory::FATAL, false])
  end

  # Returns the recovery suggestion for a given error code.
  #
  # @param code [String] an {ErrorCode} constant value
  #
  # @return [String, nil] actionable suggestion, or +nil+ if the code is unknown
  #
  # @example
  #   KubeMQ.suggestion_for(KubeMQ::ErrorCode::UNAVAILABLE)
  #   # => "Check server connectivity and firewall rules."
  def self.suggestion_for(code)
    ERROR_SUGGESTIONS[code]
  end
end
