# frozen_string_literal: true

require 'grpc'

module KubeMQ
  module Interceptors
    # gRPC client interceptor that creates OpenTelemetry spans around each RPC.
    #
    # When the OpenTelemetry SDK is loaded, wraps every call in a named span
    # with +messaging.system=kubemq+. When OpenTelemetry is not available,
    # passes through without overhead.
    #
    # Unary and server-streaming RPCs use +:client+ span kind; client-streaming
    # and bidirectional RPCs use +:producer+ span kind.
    #
    # @api private
    #
    # @see Telemetry
    # @see Telemetry::SemanticConventions
    class MetricsInterceptor < GRPC::ClientInterceptor
      def initialize
        super
        @otel_available = self.class.otel_available?
      end

      # Returns whether the OpenTelemetry API is loaded and configured.
      #
      # @return [Boolean] +true+ if +OpenTelemetry.tracer_provider+ is available
      def self.otel_available?
        defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
      end

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      def request_response(request:, call:, method:, metadata:, &block)
        return block.call(request, call, method, metadata) unless @otel_available

        with_span(method, :client) do
          block.call(request, call, method, metadata)
        end
      end

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] server response stream
      def server_streamer(request:, call:, method:, metadata:, &block)
        return block.call(request, call, method, metadata) unless @otel_available

        with_span(method, :client) do
          block.call(request, call, method, metadata)
        end
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      def client_streamer(requests:, call:, method:, metadata:, &block)
        return block.call(requests, call, method, metadata) unless @otel_available

        with_span(method, :producer) do
          block.call(requests, call, method, metadata)
        end
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] bidirectional response stream
      def bidi_streamer(requests:, call:, method:, metadata:, &block)
        return block.call(requests, call, method, metadata) unless @otel_available

        with_span(method, :producer) do
          block.call(requests, call, method, metadata)
        end
      end

      private

      def with_span(method, kind, &)
        tracer = OpenTelemetry.tracer_provider.tracer('kubemq-ruby', KubeMQ::VERSION)
        operation = method.to_s.split('/').last || method.to_s
        tracer.in_span("kubemq #{operation}", kind: kind,
                                              attributes: { 'messaging.system' => 'kubemq' }, &)
      end
    end
  end
end
