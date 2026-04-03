# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module Queues
    # Streaming sender for queue messages over a persistent gRPC upstream.
    #
    # Created via {QueuesClient#create_upstream_sender}. Keeps a
    # bidirectional stream open for high-throughput queue publishing.
    # Each {#publish} call blocks until the broker confirms receipt.
    #
    # @note This class is thread-safe. Multiple threads may call {#publish}
    #   concurrently; each waits independently for its confirmation.
    #
    # @see QueuesClient#create_upstream_sender
    # @see QueueMessage
    # @see QueueSendResult
    class UpstreamSender
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

      # Publishes one or more queue messages and waits for broker confirmation.
      #
      # Blocks until the broker confirms receipt or {SEND_TIMEOUT} elapses.
      # Accepts a single {QueueMessage} or an array for batch sending.
      #
      # @param messages [QueueMessage, Array<QueueMessage>] message(s) to publish
      # @return [Array<QueueSendResult>] confirmation results for each message
      #
      # @raise [ClientClosedError] if the sender has been closed
      # @raise [StreamBrokenError] if the upstream gRPC stream has broken
      # @raise [ValidationError] if a channel name is invalid
      # @raise [TimeoutError] if broker confirmation is not received within {SEND_TIMEOUT} seconds
      # @raise [MessageError] if the broker rejects the batch
      #
      # @see QueueMessage
      # @see QueueSendResult
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- single enqueue/wait path for stream send
      def publish(messages)
        raise ClientClosedError if @mutex.synchronize { @closed }
        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Queue upstream stream is broken; create a new sender',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        messages = [messages] unless messages.is_a?(Array)

        request_id = SecureRandom.uuid
        proto_messages = messages.map do |msg|
          Validator.validate_channel!(msg.channel, allow_wildcards: false)
          Transport::Converter.queue_message_to_proto(msg, @client_id)
        end

        proto_request = ::Kubemq::QueuesUpstreamRequest.new(
          RequestID: request_id,
          Messages: proto_messages
        )

        waiter = { mutex: Mutex.new, cv: ConditionVariable.new, result: nil }
        @pending_mutex.synchronize { @pending[request_id] = waiter }
        @request_queue.push(proto_request)

        waiter[:mutex].synchronize do
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SEND_TIMEOUT
          while waiter[:result].nil?
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            waiter[:cv].wait(waiter[:mutex], remaining)
          end
        end
        @pending_mutex.synchronize { @pending.delete(request_id) }

        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Queue upstream stream is broken; create a new sender',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        response = waiter[:result]
        raise TimeoutError, 'Queue upstream send timed out' unless response

        raise MessageError.new(response.Error, operation: 'queue_send') if response.IsError && !response.Error.empty?

        response.Results.map do |r|
          QueueSendResult.new(
            id: r.MessageID,
            sent_at: r.SentAt,
            expiration_at: r.ExpirationAt,
            delayed_to: r.DelayedTo,
            error: r.IsError ? r.Error : nil
          )
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
          responses = @transport.kubemq_client.queues_upstream(input_enum)
          responses.each do |response|
            request_id = response.RefRequestID
            @pending_mutex.synchronize do
              if (waiter = @pending[request_id])
                waiter[:mutex].synchronize do
                  waiter[:result] = response
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
