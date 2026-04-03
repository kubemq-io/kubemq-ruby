# frozen_string_literal: true

require 'grpc'

module KubeMQ
  # Maps gRPC +GRPC::BadStatus+ exceptions to typed {Error} subclasses.
  #
  # Used internally by {Interceptors::ErrorMappingInterceptor} and subscription
  # reconnect loops. Application code should rescue {Error} subclasses rather
  # than raw gRPC exceptions.
  #
  # ## gRPC Status Code Mapping
  #
  # | gRPC Code | SDK Exception | Error Code | Retryable? |
  # |-----------|--------------|------------|:----------:|
  # | CANCELLED | {CancellationError} | CANCELLED | No |
  # | UNKNOWN | {Error} | UNKNOWN | Yes |
  # | INVALID_ARGUMENT | {ValidationError} | VALIDATION_ERROR | No |
  # | DEADLINE_EXCEEDED | {TimeoutError} | CONNECTION_TIMEOUT | Yes |
  # | NOT_FOUND | {ChannelError} | NOT_FOUND | No |
  # | ALREADY_EXISTS | {ValidationError} | ALREADY_EXISTS | No |
  # | PERMISSION_DENIED | {AuthenticationError} | PERMISSION_DENIED | No |
  # | RESOURCE_EXHAUSTED | {MessageError} | RESOURCE_EXHAUSTED | Yes |
  # | FAILED_PRECONDITION | {ValidationError} | VALIDATION_ERROR | No |
  # | ABORTED | {TransactionError} | ABORTED | Yes |
  # | OUT_OF_RANGE | {ValidationError} | OUT_OF_RANGE | No |
  # | UNIMPLEMENTED | {Error} | UNIMPLEMENTED | No |
  # | INTERNAL | {Error} | INTERNAL | No |
  # | UNAVAILABLE | {ConnectionError} | UNAVAILABLE | Yes |
  # | DATA_LOSS | {Error} | DATA_LOSS | No |
  # | UNAUTHENTICATED | {AuthenticationError} | AUTH_FAILED | No |
  #
  # @see Error
  # @see ErrorCode
  module ErrorMapper
    # Maps gRPC status codes to +[exception_class, error_code, retryable]+ tuples.
    #
    # @return [Hash{Integer => Array(Class, String, Boolean)}]
    GRPC_MAPPING = {
      GRPC::Core::StatusCodes::CANCELLED =>
        [CancellationError, ErrorCode::CANCELLED, false],
      GRPC::Core::StatusCodes::UNKNOWN =>
        [KubeMQ::Error, ErrorCode::UNKNOWN, true],
      GRPC::Core::StatusCodes::INVALID_ARGUMENT =>
        [ValidationError, ErrorCode::VALIDATION_ERROR, false],
      GRPC::Core::StatusCodes::DEADLINE_EXCEEDED =>
        [KubeMQ::TimeoutError, ErrorCode::CONNECTION_TIMEOUT, true],
      GRPC::Core::StatusCodes::NOT_FOUND =>
        [ChannelError, ErrorCode::NOT_FOUND, false],
      GRPC::Core::StatusCodes::ALREADY_EXISTS =>
        [ValidationError, ErrorCode::ALREADY_EXISTS, false],
      GRPC::Core::StatusCodes::PERMISSION_DENIED =>
        [AuthenticationError, ErrorCode::PERMISSION_DENIED, false],
      GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED =>
        [MessageError, ErrorCode::RESOURCE_EXHAUSTED, true],
      GRPC::Core::StatusCodes::FAILED_PRECONDITION =>
        [ValidationError, ErrorCode::VALIDATION_ERROR, false],
      GRPC::Core::StatusCodes::ABORTED =>
        [TransactionError, ErrorCode::ABORTED, true],
      GRPC::Core::StatusCodes::OUT_OF_RANGE =>
        [ValidationError, ErrorCode::OUT_OF_RANGE, false],
      GRPC::Core::StatusCodes::UNIMPLEMENTED =>
        [KubeMQ::Error, ErrorCode::UNIMPLEMENTED, false],
      GRPC::Core::StatusCodes::INTERNAL =>
        [KubeMQ::Error, ErrorCode::INTERNAL, false],
      GRPC::Core::StatusCodes::UNAVAILABLE =>
        [ConnectionError, ErrorCode::UNAVAILABLE, true],
      GRPC::Core::StatusCodes::DATA_LOSS =>
        [KubeMQ::Error, ErrorCode::DATA_LOSS, false],
      GRPC::Core::StatusCodes::UNAUTHENTICATED =>
        [AuthenticationError, ErrorCode::AUTH_FAILED, false]
    }.freeze

    # Regex patterns for detecting credentials in error messages.
    #
    # @api private
    CREDENTIAL_PATTERNS = [
      /(?:bearer|authorization)\s*[:=]\s*\S+(?:\s+\S+)?/i,
      /eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/
    ].freeze

    module_function

    # Converts a +GRPC::BadStatus+ exception to the appropriate {Error} subclass.
    #
    # Credential patterns (bearer tokens, JWTs) are scrubbed from error messages
    # before constructing the exception. Falls back to {Error} with
    # +UNKNOWN+ code for unmapped gRPC status codes.
    #
    # @param error [GRPC::BadStatus] the gRPC exception to map
    # @param operation [String, nil] the SDK operation name for context
    #
    # @return [Error] a typed SDK error with code, suggestion, and cause chain
    def map_grpc_error(error, operation: nil)
      mapping = GRPC_MAPPING[error.code]
      unless mapping
        return KubeMQ::Error.new(
          scrub_credentials(error.details || error.message),
          code: ErrorCode::UNKNOWN,
          cause: error,
          operation: operation
        )
      end

      exc_class, error_code, retryable = mapping
      suggestion = KubeMQ.suggestion_for(error_code)

      exc_class.new(
        scrub_credentials(error.details || error.message),
        code: error_code,
        retryable: retryable,
        cause: error,
        operation: operation,
        suggestion: suggestion
      )
    end

    # Removes credential patterns from an error message string.
    #
    # Matches bearer/authorization headers and JWT tokens, replacing them
    # with +[REDACTED]+.
    #
    # @param text [String, nil] the text to scrub
    #
    # @return [String] the scrubbed text, or an empty string if +text+ is +nil+
    def scrub_credentials(text)
      return '' if text.nil?

      result = text.to_s
      CREDENTIAL_PATTERNS.each { |pattern| result = result.gsub(pattern, '[REDACTED]') }
      result
    end
  end
end
