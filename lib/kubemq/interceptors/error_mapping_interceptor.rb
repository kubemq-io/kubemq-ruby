# frozen_string_literal: true

require 'grpc'

module KubeMQ
  module Interceptors
    # gRPC client interceptor that catches +GRPC::BadStatus+ exceptions and
    # converts them to typed {Error} subclasses via {ErrorMapper}.
    #
    # Wraps all four RPC patterns (unary, server-stream, client-stream,
    # bidi-stream) so application code can rescue SDK error types rather
    # than raw gRPC exceptions.
    #
    # @api private
    #
    # @see ErrorMapper
    # @see Error
    class ErrorMappingInterceptor < GRPC::ClientInterceptor
      # Imported gRPC-to-SDK error mapping table.
      GRPC_MAPPING = ErrorMapper::GRPC_MAPPING

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      # @raise [Error] SDK-typed error mapped from gRPC status
      def request_response(request:, call:, method:, metadata:, &block)
        map_errors(method) { block.call(request, call, method, metadata) }
      end

      # @param request [Object] the outbound protobuf message
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] server response stream
      # @raise [Error] SDK-typed error mapped from gRPC status
      def server_streamer(request:, call:, method:, metadata:, &block)
        map_errors(method) { block.call(request, call, method, metadata) }
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Object] the RPC response
      # @raise [Error] SDK-typed error mapped from gRPC status
      def client_streamer(requests:, call:, method:, metadata:, &block)
        map_errors(method) { block.call(requests, call, method, metadata) }
      end

      # @param requests [Enumerator] the outbound request stream
      # @param call [GRPC::ActiveCall] the active gRPC call
      # @param method [String] the RPC method path
      # @param metadata [Hash] request metadata
      # @return [Enumerator] bidirectional response stream
      # @raise [Error] SDK-typed error mapped from gRPC status
      def bidi_streamer(requests:, call:, method:, metadata:, &block)
        map_errors(method) { block.call(requests, call, method, metadata) }
      end

      private

      def map_errors(method)
        yield
      rescue GRPC::BadStatus => e
        raise ErrorMapper.map_grpc_error(e, operation: extract_operation(method))
      end

      def extract_operation(method)
        method.to_s.split('/').last || method.to_s
      end
    end
  end
end
