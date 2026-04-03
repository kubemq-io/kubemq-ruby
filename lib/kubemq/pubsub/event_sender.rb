# frozen_string_literal: true

module KubeMQ
  module PubSub
    # Streaming sender for fire-and-forget events over a persistent gRPC stream.
    #
    # Created via {PubSubClient#create_events_sender}. Keeps a bidirectional
    # stream open for high-throughput publishing. Call {#publish} to enqueue
    # events and {#close} when finished.
    #
    # @note The stream is fire-and-forget — {#publish} returns immediately
    #   without waiting for broker confirmation.
    #
    # @see PubSubClient#create_events_sender
    # @see EventMessage
    # @see EventStoreSender
    class EventSender
      # @param transport [Transport::GrpcTransport] the gRPC transport
      # @param client_id [String] client identifier for the stream
      # @param on_error [Proc, nil] callback invoked with error results from the stream
      # @api private
      def initialize(transport:, client_id:, on_error: nil)
        @transport = transport
        @client_id = client_id
        @on_error = on_error
        @request_queue = Queue.new
        @mutex = Mutex.new
        @closed = false
        @stream_alive = true
        @stream_error = nil
        start_stream!
      end

      # Publishes an event over the persistent stream.
      #
      # The event is enqueued and sent asynchronously. This method returns
      # immediately without waiting for broker acknowledgement.
      #
      # @param message [EventMessage] the event to publish
      # @return [nil]
      #
      # @raise [ClientClosedError] if the sender has been closed
      # @raise [StreamBrokenError] if the underlying gRPC stream has broken
      # @raise [ValidationError] if channel name or content is invalid
      #
      # @see EventMessage
      def publish(message)
        raise ClientClosedError if @mutex.synchronize { @closed }
        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Event sender stream is broken; create a new sender',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        Validator.validate_channel!(message.channel, allow_wildcards: false)
        Validator.validate_content!(message.metadata, message.body)
        proto = Transport::Converter.event_to_proto(message, @client_id, store: false)
        @request_queue.push(proto)
        nil
      end

      # Closes the sender and its underlying gRPC stream.
      #
      # This method is idempotent — calling it multiple times is safe.
      #
      # @return [void]
      def close
        @mutex.synchronize do
          return if @closed

          @closed = true
        end
        wake_all_pending!
        @request_queue.push(:close)
        @stream_thread&.join(5)
      end

      private

      def start_stream!
        input_enum = Enumerator.new do |y|
          loop do
            msg = @request_queue.pop
            break if msg == :close

            y.yield(msg)
          end
        end

        @stream_thread = Thread.new do
          responses = @transport.kubemq_client.send_events_stream(input_enum)
          responses.each do |result|
            @on_error&.call(result) if !result.Error.nil? && !result.Error.empty?
          end
        rescue GRPC::BadStatus, StandardError => e
          @mutex.synchronize do
            @stream_error = e
            @stream_alive = false
          end
          @transport.on_disconnect! if e.is_a?(GRPC::Unavailable) || e.is_a?(GRPC::DeadlineExceeded)
          wake_all_pending!
        end
      end

      def wake_all_pending!
        # EventSender has no pending waiters (fire-and-forget),
        # but method exists for consistency with other senders
      end
    end
  end
end
