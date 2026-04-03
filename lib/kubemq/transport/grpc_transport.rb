# frozen_string_literal: true

require 'grpc'
require_relative '../proto/kubemq_pb'
require_relative '../proto/kubemq_services_pb'

module KubeMQ
  module Transport
    # Low-level gRPC transport managing a single broker connection.
    #
    # Handles channel creation, TLS/mTLS credential setup, keepalive options,
    # interceptor wiring, lazy connection, and coordinated shutdown. Reconnection
    # is delegated to {ReconnectManager}; connection lifecycle is tracked by
    # {ConnectionStateMachine}.
    #
    # @api private
    #
    # @see ConnectionStateMachine
    # @see ReconnectManager
    # @see MessageBuffer
    # @see Interceptors::AuthInterceptor
    class GrpcTransport
      # @!attribute [r] state_machine
      #   @return [ConnectionStateMachine] tracks connection lifecycle states
      # @!attribute [r] buffer
      #   @return [MessageBuffer] bounded buffer for messages queued during reconnection
      attr_reader :state_machine, :buffer

      # Creates a new transport bound to the given configuration.
      #
      # Connection is established lazily on the first call to {#ensure_connected!}.
      #
      # @param config [Configuration] resolved client configuration
      def initialize(config)
        @config = config
        @state_machine = ConnectionStateMachine.new
        @buffer = MessageBuffer.new
        @stub = nil
        @channel = nil
        @mutex = Mutex.new
        @connect_cv = ConditionVariable.new
        @subscriptions = []
        @last_connect_attempt = nil
        @state_machine.on_disconnected { @connect_cv.broadcast }
        @reconnect_manager = ReconnectManager.new(
          policy: @config.reconnect_policy,
          state_machine: @state_machine,
          reconnect_proc: method(:reconnect!),
          on_reconnected: method(:on_reconnected!)
        )
      end

      # Blocks until the transport reaches the READY state, connecting lazily
      # if needed. Waits on in-progress connection attempts.
      #
      # @return [void]
      # @raise [ClientClosedError] if the transport has been closed
      # @raise [ConnectionError] if the connection attempt fails
      def ensure_connected!
        return if @state_machine.ready?

        @mutex.synchronize do
          loop do
            return if @state_machine.ready?
            raise ClientClosedError if @state_machine.closed?

            if [ConnectionState::CONNECTING, ConnectionState::RECONNECTING].include?(@state_machine.state)
              @connect_cv.wait(@mutex, 15)
              next
            end
            break
          end

          connect_unlocked!
        end
      end

      # Returns the gRPC stub, connecting lazily if needed.
      #
      # @return [Kubemq::Kubemq::Stub] the active gRPC stub
      # @raise [ClientClosedError] if the transport has been closed
      # @raise [ConnectionError] if the connection attempt fails
      def kubemq_client
        ensure_connected!
        @stub
      end

      # Sends a ping to the broker and returns server information.
      #
      # @return [ServerInfo] broker host, version, and uptime
      # @raise [ConnectionError] if the broker is unreachable
      def ping
        result = @stub.ping(::Kubemq::Empty.new, deadline: default_deadline)
        ServerInfo.from_proto(result)
      end

      # Sends a pub/sub event via unary RPC.
      #
      # @param proto [Kubemq::Event] protobuf event message
      # @return [Kubemq::Result] send result from the broker
      def send_event(proto)
        kubemq_client.send_event(proto, deadline: default_deadline)
      end

      # Sends a command or query request via unary RPC.
      #
      # @param proto [Kubemq::Request] protobuf request message
      # @return [Kubemq::Response] broker response
      def send_request(proto)
        kubemq_client.send_request(proto, deadline: default_deadline)
      end

      # Sends a command/query response back to the broker via unary RPC.
      #
      # @param proto [Kubemq::Response] protobuf response message
      # @return [void]
      def send_response_rpc(proto)
        kubemq_client.send_response(proto, deadline: default_deadline)
      end

      # Sends a single queue message via unary RPC (simple API).
      #
      # @param proto [Kubemq::QueueMessage] protobuf queue message
      # @return [Kubemq::SendQueueMessageResult] send result
      def send_queue_message_rpc(proto)
        kubemq_client.send_queue_message(proto, deadline: default_deadline)
      end

      # Sends a batch of queue messages via unary RPC (simple API).
      #
      # @param proto [Kubemq::QueueMessagesBatchRequest] protobuf batch request
      # @return [Kubemq::QueueMessagesBatchResponse] batch send results
      def send_queue_messages_batch_rpc(proto)
        kubemq_client.send_queue_messages_batch(proto, deadline: default_deadline)
      end

      # Receives queue messages via unary RPC (simple API).
      #
      # @param proto [Kubemq::ReceiveQueueMessagesRequest] protobuf receive request
      # @return [Kubemq::ReceiveQueueMessagesResponse] received messages
      def receive_queue_messages_rpc(proto)
        kubemq_client.receive_queue_messages(proto, deadline: default_deadline)
      end

      # Acknowledges all messages in a queue channel via unary RPC.
      #
      # @param proto [Kubemq::AckAllQueueMessagesRequest] protobuf ack-all request
      # @return [Kubemq::AckAllQueueMessagesResponse] ack result with affected count
      def ack_all_queue_messages_rpc(proto)
        kubemq_client.ack_all_queue_messages(proto, deadline: default_deadline)
      end

      # Closes the transport and releases all resources.
      #
      # Transitions the state machine to CLOSED, stops the reconnect manager,
      # cancels active subscriptions, flushes the message buffer, and closes
      # the gRPC channel. This method is idempotent.
      #
      # @return [void]
      def close
        @mutex.synchronize do
          return if @state_machine.closed?

          begin
            @state_machine.transition!(ConnectionState::CLOSED, reason: 'client closed')
          rescue KubeMQ::Error
            return
          end
        end

        @reconnect_manager.stop
        cancel_subscriptions
        flush_buffer(timeout: 5)

        begin
          @channel&.close
        rescue StandardError
          # best-effort
        end

        @connect_cv.broadcast
      end

      # Returns whether the transport has been closed.
      #
      # @return [Boolean] +true+ if {#close} has been called
      def closed?
        @state_machine.closed?
      end

      # Registers a subscription thread for lifecycle tracking.
      #
      # @param thread [Thread] the subscription background thread
      # @return [void]
      def register_subscription(thread)
        @mutex.synchronize { @subscriptions << thread }
      end

      # Removes a subscription thread from lifecycle tracking.
      #
      # @param thread [Thread] the subscription background thread to remove
      # @return [void]
      def unregister_subscription(thread)
        @mutex.synchronize { @subscriptions.delete(thread) }
      end

      # Tears down and rebuilds the gRPC channel and stub.
      #
      # Used by the reconnect manager after a connection loss.
      #
      # @return [void]
      # @raise [ConnectionError] if the new connection attempt fails
      def recreate_channel!
        @mutex.synchronize do
          unless @state_machine.state == ConnectionState::RECONNECTING
            begin
              @state_machine.transition!(ConnectionState::RECONNECTING, reason: 'channel recreation')
            rescue KubeMQ::Error
              # allow from any state for recreation
            end
          end
          begin
            @channel&.close
          rescue StandardError
            # best-effort
          end
          @channel = nil
          @stub = nil
          connect_unlocked!
        end
      end

      # Signals a connection loss and starts the reconnect manager.
      #
      # Transitions to RECONNECTING and spawns the background reconnect loop.
      # No-op if the transport is already closed.
      #
      # @return [void]
      def on_disconnect!
        return if @state_machine.closed?

        begin
          @state_machine.transition!(ConnectionState::RECONNECTING, reason: 'connection lost')
        rescue KubeMQ::Error
          return
        end
        @reconnect_manager.start
      end

      private

      def connect!
        @mutex.synchronize { connect_unlocked! }
      end

      def connect_unlocked!
        enforce_connect_backoff!
        build_channel_and_stub!
        validate_connection_unlocked!(@channel, @stub)
      rescue KubeMQ::ConnectionError
        raise
      rescue StandardError => e
        begin
          @channel&.close
        rescue StandardError
          nil
        end
        @channel = nil
        @stub = nil
        begin
          @state_machine.transition!(ConnectionState::IDLE, reason: e.message)
        rescue KubeMQ::Error
          # ignore invalid transition
        end
        raise ConnectionError.new(
          "Failed to connect to #{@config.address}: #{ErrorMapper.scrub_credentials(e.message)}",
          code: ErrorCode::UNAVAILABLE,
          cause: e,
          operation: 'connect',
          suggestion: KubeMQ.suggestion_for(ErrorCode::UNAVAILABLE)
        )
      ensure
        @connect_cv.broadcast
      end

      def default_deadline
        Time.now + @config.default_timeout
      end

      def build_channel_and_stub!
        @state_machine.transition!(ConnectionState::CONNECTING)
        credentials = create_channel_credentials
        options = channel_options
        interceptors = create_interceptors

        @channel = GRPC::Core::Channel.new(@config.address, options, credentials)
        @stub = ::Kubemq::Kubemq::Stub.new(
          @config.address,
          credentials,
          channel_override: @channel,
          interceptors: interceptors
        )
      end

      def validate_connection_unlocked!(channel, stub)
        result = stub.ping(::Kubemq::Empty.new, deadline: Time.now + 10)
        @state_machine.transition!(ConnectionState::READY, server_info: ServerInfo.from_proto(result))
      rescue GRPC::BadStatus, GRPC::Core::CallError, IOError, SocketError, SystemCallError, Errno::ECONNREFUSED => e
        begin
          channel&.close
        rescue StandardError
          nil
        end
        @channel = nil
        @stub = nil
        begin
          @state_machine.transition!(ConnectionState::IDLE, reason: e.message)
        rescue KubeMQ::Error
          # ignore invalid transition
        end
        raise ConnectionError.new(
          "Failed to connect to #{@config.address}: #{ErrorMapper.scrub_credentials(e.message)}",
          code: ErrorCode::UNAVAILABLE,
          cause: e,
          operation: 'connect',
          suggestion: KubeMQ.suggestion_for(ErrorCode::UNAVAILABLE)
        )
      end

      def enforce_connect_backoff!
        if @last_connect_attempt && (Time.now - @last_connect_attempt) < 1.0
          sleep(1.0 - (Time.now - @last_connect_attempt))
        end
        @last_connect_attempt = Time.now
      end

      def channel_options
        opts = {
          'grpc.max_send_message_length' => @config.max_send_size,
          'grpc.max_receive_message_length' => @config.max_receive_size
        }

        if @config.keepalive.enabled
          opts['grpc.keepalive_time_ms'] = @config.keepalive.ping_interval_seconds * 1000
          opts['grpc.keepalive_timeout_ms'] = @config.keepalive.ping_timeout_seconds * 1000
          opts['grpc.keepalive_permit_without_calls'] = @config.keepalive.permit_without_calls ? 1 : 0
        end

        if @config.tls&.insecure_skip_verify
          host = @config.address.split(':').first
          opts['grpc.ssl_target_name_override'] = host
        end

        opts
      end

      def create_channel_credentials
        if @config.tls.enabled
          if @config.tls.insecure_skip_verify
            GRPC::Core::ChannelCredentials.new
          elsif @config.tls.cert_file && @config.tls.key_file
            root_certs = @config.tls.ca_file ? File.read(@config.tls.ca_file) : nil
            private_key = File.read(@config.tls.key_file)
            cert_chain = File.read(@config.tls.cert_file)
            GRPC::Core::ChannelCredentials.new(root_certs, private_key, cert_chain)
          elsif @config.tls.ca_file
            root_certs = File.read(@config.tls.ca_file)
            GRPC::Core::ChannelCredentials.new(root_certs)
          else
            GRPC::Core::ChannelCredentials.new
          end
        else
          :this_channel_is_insecure
        end
      end

      def create_interceptors
        interceptors = []
        interceptors << Interceptors::AuthInterceptor.new(@config.auth_token)
        interceptors << Interceptors::MetricsInterceptor.new
        interceptors << Interceptors::RetryInterceptor.new
        interceptors << Interceptors::ErrorMappingInterceptor.new
        interceptors
      end

      def cancel_subscriptions
        threads = @mutex.synchronize { @subscriptions.dup }
        threads.each do |t|
          t[:cancellation_token]&.cancel if t.respond_to?(:[])
          begin; t[:grpc_call]&.cancel; rescue StandardError; end
          t.join(5)
        end
      end

      def flush_buffer(timeout: 5)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        @buffer.drain do |_msg|
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        end
      end

      def reconnect!
        recreate_channel!
      end

      def on_reconnected!
        # Subscriptions auto-reconnect via their own loops (H-7)
      end
    end
  end
end
