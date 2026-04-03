# frozen_string_literal: true

require 'grpc'

module KubeMQ
  module Interceptors
    # gRPC client interceptor that retries failed unary RPCs with exponential backoff.
    #
    # Only unary (+request_response+) calls are retried; streaming RPCs pass
    # through unchanged because retrying a partial stream is not safe.
    #
    # Retryable gRPC status codes: +UNAVAILABLE+, +ABORTED+, +DEADLINE_EXCEEDED+.
    #
    # @api private
    #
    # @see ErrorMappingInterceptor
    # @see ReconnectManager
    class RetryInterceptor < GRPC::ClientInterceptor
      # gRPC status codes eligible for automatic retry.
      RETRYABLE_CODES = [
        GRPC::Core::StatusCodes::UNAVAILABLE,
        GRPC::Core::StatusCodes::ABORTED,
        GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
      ].freeze

      # Maximum number of retry attempts for unary RPCs.
      DEFAULT_MAX_RETRIES = 3

      # Initial backoff delay in seconds.
      DEFAULT_BASE_DELAY = 0.1

      # Multiplier applied to delay after each retry attempt.
      DEFAULT_MULTIPLIER = 2.0

      # @param max_retries [Integer] maximum retry attempts (default: {DEFAULT_MAX_RETRIES})
      # @param base_delay [Float] initial backoff delay in seconds (default: {DEFAULT_BASE_DELAY})
      # @param multiplier [Float] exponential backoff multiplier (default: {DEFAULT_MULTIPLIER})
      def initialize(max_retries: DEFAULT_MAX_RETRIES, base_delay: DEFAULT_BASE_DELAY,
                     multiplier: DEFAULT_MULTIPLIER)
        super()
        @max_retries = max_retries
        @base_delay = base_delay
        @multiplier = multiplier
      end

      # Executes a unary RPC with automatic retry on transient failures.
      #
      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      # @raise [GRPC::BadStatus] after exhausting retries or on non-retryable errors
      def request_response(request:, call:, method:, metadata:, &block)
        with_retry { block.call(request, call, method, metadata) }
      end

      # Passes server-streaming RPCs through without retry.
      #
      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] server response stream
      def server_streamer(request:, call:, method:, metadata:, &block)
        block.call(request, call, method, metadata)
      end

      # Passes client-streaming RPCs through without retry.
      #
      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      def client_streamer(requests:, call:, method:, metadata:, &block)
        block.call(requests, call, method, metadata)
      end

      # Passes bidirectional-streaming RPCs through without retry.
      #
      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] bidirectional response stream
      def bidi_streamer(requests:, call:, method:, metadata:, &block)
        block.call(requests, call, method, metadata)
      end

      private

      def with_retry
        attempt = 0
        last_error = nil
        begin
          yield
        rescue GRPC::Core::CallError
          raise last_error if last_error

          raise
        rescue GRPC::BadStatus => e
          last_error = e
          attempt += 1
          if attempt <= @max_retries && retryable?(e)
            delay = @base_delay * (@multiplier**(attempt - 1))
            sleep(delay)
            retry
          end
          raise
        end
      end

      def retryable?(error)
        RETRYABLE_CODES.include?(error.code)
      end
    end
  end
end
