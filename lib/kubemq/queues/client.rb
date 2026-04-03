# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  # Client for KubeMQ message queues — guaranteed delivery with acknowledgement.
  #
  # Provides two APIs: a **stream API** (primary, recommended) using persistent
  # gRPC bidirectional streams for high throughput, and a **simple API**
  # (secondary) using unary RPCs for low-volume use cases.
  #
  # Inherits connection management and channel CRUD from {BaseClient}.
  #
  # @example Stream API — send and poll
  #   client = KubeMQ::QueuesClient.new(address: "localhost:50000")
  #
  #   msg = KubeMQ::Queues::QueueMessage.new(channel: "tasks", body: "work-item")
  #   client.send_queue_message_stream(msg)
  #
  #   request = KubeMQ::Queues::QueuePollRequest.new(
  #     channel: "tasks", max_items: 10, wait_timeout: 5
  #   )
  #   response = client.poll(request)
  #   response.messages.each do |m|
  #     process(m.body)
  #     m.ack
  #   end
  #   client.close
  #
  # @see Queues::QueueMessage
  # @see Queues::QueuePollRequest
  # @see Queues::QueuePollResponse
  class QueuesClient < BaseClient
    def initialize(address: nil, client_id: nil, auth_token: nil, config: nil, **options)
      super
      @mutex = Mutex.new
      @closed = false
      @stream_mutex = Mutex.new
      @upstream_sender = nil
      @downstream_receiver = nil
    end

    # --- Stream API (Primary) ---

    # Creates a new upstream sender for publishing queue messages over a
    # persistent gRPC stream.
    #
    # @return [Queues::UpstreamSender] streaming sender bound to this client
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see Queues::UpstreamSender
    def create_upstream_sender
      ensure_connected!
      Queues::UpstreamSender.new(transport: @transport, client_id: @config.client_id)
    end

    # Creates a new downstream receiver for polling queue messages over a
    # persistent gRPC stream.
    #
    # @return [Queues::DownstreamReceiver] streaming receiver bound to this client
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see Queues::DownstreamReceiver
    def create_downstream_receiver
      ensure_connected!
      Queues::DownstreamReceiver.new(transport: @transport, client_id: @config.client_id)
    end

    # Sends a single queue message via the stream API.
    #
    # Lazily creates an internal {Queues::UpstreamSender} on first call.
    # If the stream breaks, the sender is reset and a {StreamBrokenError}
    # is raised — retry the call to establish a new stream.
    #
    # @param message [Queues::QueueMessage] message to enqueue
    #
    # @return [Queues::QueueSendResult] send confirmation with timestamp
    #
    # @raise [ValidationError] if the channel name is invalid
    # @raise [StreamBrokenError] if the upstream gRPC stream broke
    #
    # @note Auto-creates an upstream sender on first call.
    #
    # @see Queues::QueueMessage
    # @see Queues::QueueSendResult
    def send_queue_message_stream(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      sender = @stream_mutex.synchronize do
        @upstream_sender ||= create_upstream_sender
      end
      results = sender.publish([message])
      results.first
    rescue StreamBrokenError
      @stream_mutex.synchronize { @upstream_sender = nil }
      raise
    end

    # Polls for queue messages using the stream API.
    #
    # Lazily creates an internal {Queues::DownstreamReceiver} on first call.
    # If the stream breaks, the receiver is reset and a {StreamBrokenError}
    # is raised — retry the call to establish a new stream.
    #
    # @param request [Queues::QueuePollRequest] poll parameters (channel,
    #   max_items, wait_timeout, auto_ack)
    #
    # @return [Queues::QueuePollResponse] response containing messages and
    #   batch-level action methods
    #
    # @raise [StreamBrokenError] if the downstream gRPC stream broke
    # @raise [TimeoutError] if the poll wait timeout expires with no messages
    #
    # @example
    #   request = KubeMQ::Queues::QueuePollRequest.new(
    #     channel: "tasks", max_items: 10, wait_timeout: 5
    #   )
    #   response = client.poll(request)
    #   response.messages.each { |m| m.ack }
    #
    # @see Queues::QueuePollRequest
    # @see Queues::QueuePollResponse
    def poll(request)
      receiver = @stream_mutex.synchronize do
        @downstream_receiver ||= create_downstream_receiver
      end
      receiver.poll(request)
    rescue StreamBrokenError
      @stream_mutex.synchronize { @downstream_receiver = nil }
      raise
    end

    # --- Simple API (Secondary) ---

    # Sends a single queue message via a unary RPC call.
    #
    # For higher throughput, prefer {#send_queue_message_stream} or
    # {#create_upstream_sender} instead.
    #
    # @param message [Queues::QueueMessage] message to enqueue
    #
    # @return [Queues::QueueSendResult] send confirmation with timestamp
    #
    # @raise [ValidationError] if the channel name is invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see Queues::QueueMessage
    # @see Queues::QueueSendResult
    def send_queue_message(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      ensure_connected!

      proto = Transport::Converter.queue_message_to_proto(message, @config.client_id)
      result = @transport.kubemq_client.send_queue_message(proto)

      Queues::QueueSendResult.new(
        id: result.MessageID,
        sent_at: result.SentAt,
        expiration_at: result.ExpirationAt,
        delayed_to: result.DelayedTo,
        error: result.IsError ? result.Error : nil
      )
    end

    # Sends multiple queue messages in a single batch via a unary RPC call.
    #
    # @param messages [Array<Queues::QueueMessage>] messages to enqueue
    # @param batch_id [String, nil] identifier for this batch
    #   (auto-generated UUID if nil)
    #
    # @return [Array<Queues::QueueSendResult>] per-message send results
    #
    # @raise [ValidationError] if +messages+ is empty or any channel is invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see Queues::QueueMessage
    # @see Queues::QueueSendResult
    def send_queue_messages_batch(messages, batch_id: nil)
      raise ValidationError, 'messages cannot be empty' if messages.nil? || messages.empty?

      ensure_connected!

      proto_messages = messages.map do |msg|
        Validator.validate_channel!(msg.channel, allow_wildcards: false)
        Transport::Converter.queue_message_to_proto(msg, @config.client_id)
      end

      batch_request = ::Kubemq::QueueMessagesBatchRequest.new(
        BatchID: batch_id || SecureRandom.uuid,
        Messages: proto_messages
      )

      response = @transport.kubemq_client.send_queue_messages_batch(batch_request)
      response.Results.map do |r|
        Queues::QueueSendResult.new(
          id: r.MessageID,
          sent_at: r.SentAt,
          expiration_at: r.ExpirationAt,
          delayed_to: r.DelayedTo,
          error: r.IsError ? r.Error : nil
        )
      end
    end

    # Receives queue messages via a unary RPC call (simple API).
    #
    # For higher throughput and transactional ack/nack/requeue, prefer the
    # stream-based {#poll} method instead.
    #
    # @param channel [String] queue channel to receive from
    # @param max_messages [Integer] maximum number of messages to return
    #   (default: +1+)
    # @param wait_timeout_seconds [Integer] seconds to wait for messages
    #   before returning empty (default: +1+)
    # @param peek [Boolean] if +true+, messages are not removed from the queue
    #   (default: +false+)
    #
    # @return [Array<Queues::QueueMessageReceived>] received messages
    #
    # @raise [ValidationError] if the channel name or parameters are invalid
    # @raise [MessageError] if the broker returns an error
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @note +wait_timeout_seconds+ is in seconds.
    #
    # @example
    #   messages = client.receive_queue_messages(
    #     channel: "tasks",
    #     max_messages: 5,
    #     wait_timeout_seconds: 10
    #   )
    #   messages.each { |m| puts m.body }
    #
    # @see Queues::QueueMessageReceived
    def receive_queue_messages(channel:, max_messages: 1, wait_timeout_seconds: 1, peek: false)
      Validator.validate_channel!(channel, allow_wildcards: false)
      Validator.validate_queue_receive!(max_messages, wait_timeout_seconds)
      ensure_connected!

      request = ::Kubemq::ReceiveQueueMessagesRequest.new(
        RequestID: SecureRandom.uuid,
        ClientID: @config.client_id,
        Channel: channel,
        MaxNumberOfMessages: max_messages,
        WaitTimeSeconds: wait_timeout_seconds,
        IsPeak: peek
      )

      response = @transport.kubemq_client.receive_queue_messages(request)

      if response.IsError && !response.Error.empty?
        raise MessageError.new(response.Error, operation: 'receive_queue_messages', channel: channel)
      end

      (response.Messages || []).map do |msg|
        hash = Transport::Converter.proto_to_queue_message_received(msg)
        attrs = (Queues::QueueMessageAttributes.new(**hash[:attributes]) if hash[:attributes])
        Queues::QueueMessageReceived.new(
          id: hash[:id],
          channel: hash[:channel],
          metadata: hash[:metadata],
          body: hash[:body],
          tags: hash[:tags],
          attributes: attrs
        )
      end
    end

    # Acknowledges all pending messages in a queue channel.
    #
    # @param channel [String] queue channel to acknowledge
    # @param wait_timeout_seconds [Integer] seconds to wait for the operation
    #   to complete (default: +1+)
    #
    # @return [Integer] number of affected messages
    #
    # @raise [ValidationError] if the channel name is invalid
    # @raise [MessageError] if the broker returns an error
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @note +wait_timeout_seconds+ is in seconds.
    def ack_all_queue_messages(channel:, wait_timeout_seconds: 1)
      Validator.validate_channel!(channel, allow_wildcards: false)
      ensure_connected!

      request = ::Kubemq::AckAllQueueMessagesRequest.new(
        RequestID: SecureRandom.uuid,
        ClientID: @config.client_id,
        Channel: channel,
        WaitTimeSeconds: wait_timeout_seconds
      )

      response = @transport.kubemq_client.ack_all_queue_messages(request)

      if response.IsError && !response.Error.empty?
        raise MessageError.new(response.Error, operation: 'ack_all_queue_messages', channel: channel)
      end

      response.AffectedMessages
    end

    # --- Channel Management Convenience ---

    # Creates a queues channel on the broker.
    #
    # @param channel_name [String] name for the new channel
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#create_channel
    def create_queues_channel(channel_name:)
      create_channel(channel_name: channel_name, channel_type: ChannelType::QUEUES)
    end

    # Deletes a queues channel from the broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#delete_channel
    def delete_queues_channel(channel_name:)
      delete_channel(channel_name: channel_name, channel_type: ChannelType::QUEUES)
    end

    # Lists queues channels, with optional name filtering.
    #
    # @param search [String, nil] substring filter for channel names
    # @return [Array<ChannelInfo>] matching channels with metadata
    # @raise [ClientClosedError] if the client has been closed
    # @see BaseClient#list_channels
    def list_queues_channels(search: nil)
      list_channels(channel_type: ChannelType::QUEUES, search: search)
    end

    # Closes the client, all open stream senders/receivers, and releases resources.
    #
    # Closes any internal {Queues::UpstreamSender} and
    # {Queues::DownstreamReceiver} before closing the transport.
    # This method is idempotent.
    #
    # @return [void]
    def close
      @mutex.synchronize do
        return if @closed

        @closed = true
      end
      @stream_mutex.synchronize do
        begin; @upstream_sender&.close; rescue StandardError; end
        @upstream_sender = nil
        begin; @downstream_receiver&.close; rescue StandardError; end
        @downstream_receiver = nil
      end
    ensure
      super
    end
  end
end
