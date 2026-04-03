# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  module Queues
    # Streaming receiver for queue messages over a persistent gRPC downstream.
    #
    # Created via {QueuesClient#create_downstream_receiver}. Keeps a
    # bidirectional stream open for polling with transactional
    # acknowledgement. Call {#poll} to receive messages and use the
    # returned {QueuePollResponse} for batch or per-message actions.
    #
    # @note This class is thread-safe. Multiple threads may call {#poll}
    #   concurrently; each waits independently for its response.
    #
    # @see QueuesClient#create_downstream_receiver
    # @see QueuePollRequest
    # @see QueuePollResponse
    class DownstreamReceiver
      # Maximum seconds to wait for a downstream response.
      RESPONSE_TIMEOUT = 60

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

      # Polls the queue channel for messages.
      #
      # Blocks until messages arrive or the request's +wait_timeout+ elapses.
      # Returns a {QueuePollResponse} with received messages and transaction
      # action methods.
      #
      # @param request [QueuePollRequest] poll configuration
      # @return [QueuePollResponse] received messages and transaction handle
      #
      # @raise [ClientClosedError] if the receiver has been closed
      # @raise [StreamBrokenError] if the downstream gRPC stream has broken
      # @raise [ValidationError] if the channel name or poll parameters are invalid
      # @raise [TimeoutError] if no response is received within the timeout
      #
      # @see QueuePollRequest
      # @see QueuePollResponse
      def poll(request)
        raise ClientClosedError if @mutex.synchronize { @closed }
        unless @mutex.synchronize { @stream_alive }
          raise StreamBrokenError.new(
            'Queue downstream stream is broken',
            cause: @mutex.synchronize { @stream_error }
          )
        end

        Validator.validate_channel!(request.channel, allow_wildcards: false)
        Validator.validate_queue_poll!(request.max_items, request.wait_timeout)

        request_id = SecureRandom.uuid
        proto_request = ::Kubemq::QueuesDownstreamRequest.new(
          RequestID: request_id,
          ClientID: @client_id,
          RequestTypeData: :Get,
          Channel: request.channel,
          MaxItems: request.max_items,
          WaitTimeout: request.wait_timeout * 1000,
          AutoAck: request.auto_ack
        )

        timeout = [request.wait_timeout + 5, RESPONSE_TIMEOUT].min
        response = send_and_wait(request_id, proto_request, timeout)
        raise TimeoutError, 'Queue poll timed out' unless response

        build_poll_response(response)
      end

      # Sends a transaction action over the downstream stream.
      #
      # @param transaction_id [String] the transaction to act upon
      # @param type [Symbol] action type (e.g., +:AckAll+, +:NAckAll+, +:ReQueueAll+)
      # @param channel [String, nil] destination channel for requeue actions
      # @param sequence_range [Array<Integer>] message sequences for range actions
      # @return [Object, nil] the broker response, if any
      #
      # @raise [ClientClosedError] if the receiver has been closed
      # @api private
      def send_action(transaction_id:, type:, channel: nil, sequence_range: [])
        raise ClientClosedError, 'Downstream receiver is closed' if @mutex.synchronize { @closed }

        request_id = SecureRandom.uuid
        proto_request = ::Kubemq::QueuesDownstreamRequest.new(
          RequestID: request_id,
          ClientID: @client_id,
          RequestTypeData: type,
          RefTransactionId: transaction_id,
          ReQueueChannel: channel || '',
          SequenceRange: sequence_range
        )

        send_and_wait(request_id, proto_request, 10)
      end

      # Closes the receiver and its underlying gRPC stream.
      #
      # Sends a close-by-client request to the broker and shuts down the
      # stream. This method is idempotent — calling it multiple times is safe.
      #
      # @return [void]
      def close
        @mutex.synchronize do
          return if @closed

          @closed = true
        end
        wake_all_pending!

        begin
          close_request = ::Kubemq::QueuesDownstreamRequest.new(
            RequestID: SecureRandom.uuid,
            ClientID: @client_id,
            RequestTypeData: :CloseByClient
          )
          @request_queue.push(close_request)
          sleep(0.5)
        rescue StandardError
          # best-effort
        end

        @request_queue.push(:close)
        @stream_thread&.join(5)
      end

      private

      def send_and_wait(request_id, proto_request, timeout)
        waiter = { mutex: Mutex.new, cv: ConditionVariable.new, result: nil }
        @pending_mutex.synchronize { @pending[request_id] = waiter }
        @request_queue.push(proto_request)

        waiter[:mutex].synchronize do
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          while waiter[:result].nil?
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            waiter[:cv].wait(waiter[:mutex], remaining)
          end
        end
        @pending_mutex.synchronize { @pending.delete(request_id) }

        waiter[:result]
      end

      def start_stream!
        input_enum = Enumerator.new do |y|
          loop do
            msg = @request_queue.pop
            break if msg == :close

            y.yield(msg)
          end
        end

        @stream_thread = Thread.new do
          responses = @transport.kubemq_client.queues_downstream(input_enum)
          responses.each do |response|
            request_id = response.RefRequestId
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

      # rubocop:disable Metrics/MethodLength -- builds poll response + per-message action_proc
      def build_poll_response(response)
        transaction_id = response.TransactionId

        action_proc = lambda { |type, channel: nil, sequence_range: []|
          send_action(
            transaction_id: transaction_id,
            type: type,
            channel: channel,
            sequence_range: sequence_range
          )
        }

        messages = response.Messages.map do |msg|
          hash = Transport::Converter.proto_to_queue_message_received(msg)
          attrs = (QueueMessageAttributes.new(**hash[:attributes]) if hash[:attributes])
          seq = attrs&.sequence || 0
          QueueMessageReceived.new(
            id: hash[:id],
            channel: hash[:channel],
            metadata: hash[:metadata],
            body: hash[:body],
            tags: hash[:tags],
            attributes: attrs,
            action_proc: action_proc,
            sequence: seq
          )
        end

        QueuePollResponse.new(
          transaction_id: transaction_id,
          messages: messages,
          error: response.IsError ? response.Error : nil,
          active_offsets: response.ActiveOffsets.to_a,
          transaction_complete: response.TransactionComplete,
          action_proc: action_proc
        )
      end
      # rubocop:enable Metrics/MethodLength

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
