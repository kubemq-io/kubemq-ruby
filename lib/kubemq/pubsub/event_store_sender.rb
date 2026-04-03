# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module PubSub
    # Streaming sender for durable events store over a persistent gRPC stream.
    #
    # Created via {PubSubClient#create_events_store_sender}. Unlike
    # {EventSender}, each {#publish} call blocks until the broker confirms
    # persistence, returning an {EventStoreResult}.
    #
    # @note This class is thread-safe. Multiple threads may call {#publish}
    #   concurrently; each waits independently for its confirmation.
    #
    # @see PubSubClient#create_events_store_sender
    # @see EventStoreMessage
    # @see EventStoreResult
    # @see EventSender
    class EventStoreSender
      # Maximum seconds to wait for broker confirmation per publish.
      SEND_TIMEOUT = 10

      # @param transport [Transport::GrpcTransport] the gRPC transport
      # @param client_id [String] client identifier for the stream
      # @api private
      def initialize(transport:, client_id:)
        @transport = transport
        @client_id = client_id
        @request_queue = Queue.new
        @pending = {}
        @pending_mutex = Mutex.new
        @mutex = Mutex.new
        @closed = false
        @stream_alive = true
        @stream_error = nil
        start_stream!
      end

      # Publishes a durable event and waits for broker confirmation.
      #
      # Blocks until the broker confirms persistence or the {SEND_TIMEOUT}
      # elapses. Returns an {EventStoreResult} on success.
      #
      # @param message [EventStoreMessage] the event to publish
      # @return [EventStoreResult] confirmation with +id+, +sent+, and optional +error+
      #
      # @raise [ClientClosedError] if the sender has been closed
      # @raise [StreamBrokenError] if the underlying gRPC stream has broken
      # @raise [ValidationError] if channel name or content is invalid
      # @raise [TimeoutError] if broker confirmation is not received within {SEND_TIMEOUT} seconds
      #
      # @see EventStoreMessage
      # @see EventStoreResult
      def publish(message)
        raise ClientClosedError if @mutex.synchronize { @closed }
        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Event store sender stream is broken; create a new sender',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        Validator.validate_channel!(message.channel, allow_wildcards: false)
        Validator.validate_content!(message.metadata, message.body)
        proto = Transport::Converter.event_to_proto(message, @client_id, store: true)
        event_id = proto.EventID

        waiter = { mutex: Mutex.new, cv: ConditionVariable.new, result: nil }
        @pending_mutex.synchronize { @pending[event_id] = waiter }
        @request_queue.push(proto)

        waiter[:mutex].synchronize do
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SEND_TIMEOUT
          while waiter[:result].nil?
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            waiter[:cv].wait(waiter[:mutex], remaining)
          end
        end
        @pending_mutex.synchronize { @pending.delete(event_id) }

        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Event store sender stream is broken; create a new sender',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        result = waiter[:result]
        raise TimeoutError, "EventStore send timed out for event #{event_id}" unless result

        EventStoreResult.new(
          id: result.EventID,
          sent: result.Sent,
          error: result.Error.empty? ? nil : result.Error
        )
      end

      # Closes the sender and its underlying gRPC stream.
      #
      # Wakes any threads blocked in {#publish} and shuts down the stream.
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
            event_id = result.EventID
            @pending_mutex.synchronize do
              if (waiter = @pending[event_id])
                waiter[:mutex].synchronize do
                  waiter[:result] = result
                  waiter[:cv].signal
                end
              end
            end
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
        @pending_mutex.synchronize do
          @pending.each_value do |waiter|
            waiter[:mutex].synchronize do
              waiter[:cv].signal
            end
          end
        end
      end
    end
  end
end
