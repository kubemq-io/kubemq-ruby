# frozen_string_literal: true

require 'grpc'

module KubeMQ
  module Interceptors
    # gRPC client interceptor that injects a bearer authentication token
    # into outbound request metadata.
    #
    # Skips injection for Ping RPCs (which do not require authentication)
    # and when no token is configured.
    #
    # @api private
    #
    # @see Configuration#auth_token
    # @see GrpcTransport
    class AuthInterceptor < GRPC::ClientInterceptor
      # @param auth_token [String, nil] bearer token to inject into metadata
      def initialize(auth_token)
        super()
        @auth_token = auth_token
      end

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] mutable request metadata
      # @return [Object] the RPC response
      def request_response(request:, call:, method:, metadata:, &block)
        inject_auth!(metadata, method)
        block.call(request, call, method, metadata)
      end

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] mutable request metadata
      # @return [Enumerator] server response stream
      def server_streamer(request:, call:, method:, metadata:, &block)
        inject_auth!(metadata, method)
        block.call(request, call, method, metadata)
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] mutable request metadata
      # @return [Object] the RPC response
      def client_streamer(requests:, call:, method:, metadata:, &block)
        inject_auth!(metadata, method)
        block.call(requests, call, method, metadata)
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] mutable request metadata
      # @return [Enumerator] bidirectional response stream
      def bidi_streamer(requests:, call:, method:, metadata:, &block)
        inject_auth!(metadata, method)
        block.call(requests, call, method, metadata)
      end

      private

      def inject_auth!(metadata, method)
        return if @auth_token.nil? || @auth_token.empty?
        return if ping_method?(method)

        metadata['authorization'] = @auth_token
      end

      def ping_method?(method)
        method.to_s.end_with?('/Ping')
      end
    end
  end
end
