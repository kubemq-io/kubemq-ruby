# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  # Client for KubeMQ pub/sub messaging — events (fire-and-forget) and
  # events store (durable with replay).
  #
  # Inherits connection management and channel CRUD from {BaseClient}.
  # Subscription methods run on background threads and accept a block for
  # incoming messages.
  #
  # @example Send and subscribe to events
  #   client = KubeMQ::PubSubClient.new(address: "localhost:50000")
  #
  #   token = KubeMQ::CancellationToken.new
  #   sub = KubeMQ::PubSub::EventsSubscription.new(channel: "notifications")
  #   client.subscribe_to_events(sub, cancellation_token: token) do |event|
  #     puts "Received: #{event.body}"
  #   end
  #
  #   client.send_event(
  #     KubeMQ::PubSub::EventMessage.new(channel: "notifications", body: "hello")
  #   )
  #   sleep 1
  #   token.cancel
  #   client.close
  #
  # @see PubSub::EventMessage
  # @see PubSub::EventsSubscription
  # @see PubSub::EventsStoreSubscription
  class PubSubClient < BaseClient
    def initialize(**kwargs)
      super
      @senders = []
      @senders_mutex = Mutex.new
    end

    # Sends a single event to a channel. Fire-and-forget semantics — the
    # server does not guarantee persistence.
    #
    # @param message [PubSub::EventMessage] event to send
    #
    # @return [PubSub::EventSendResult] send confirmation with error status
    #
    # @raise [ValidationError] if channel name or content is invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @example
    #   msg = KubeMQ::PubSub::EventMessage.new(
    #     channel: "events.orders",
    #     metadata: "order-created",
    #     body: '{"id": 42}',
    #     tags: { "env" => "production" }
    #   )
    #   result = client.send_event(msg)
    #   puts "Sent: #{result.id}" if result.sent
    #
    # @see PubSub::EventMessage
    # @see PubSub::EventSendResult
    def send_event(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      Validator.validate_content!(message.metadata, message.body)
      ensure_connected!

      proto = Transport::Converter.event_to_proto(message, @config.client_id, store: false)
      result = @transport.kubemq_client.send_event(proto)
      hash = Transport::Converter.proto_to_event_result(result)
      PubSub::EventSendResult.new(**hash)
    end

    # Creates a streaming event sender for high-throughput publishing.
    #
    # The sender holds a persistent gRPC stream open. Close it explicitly
    # when finished, or it will be closed when the client is closed.
    #
    # @param on_error [Proc, nil] callback receiving {Error} on stream failures
    #
    # @return [PubSub::EventSender] streaming sender bound to this client
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see PubSub::EventSender
    def create_events_sender(on_error: nil)
      ensure_connected!
      sender = PubSub::EventSender.new(transport: @transport, client_id: @config.client_id, on_error: on_error)
      senders_mutex.synchronize { senders_list << sender }
      sender
    end

    # Subscribes to real-time events on a channel. Runs on a background
    # thread; incoming events are delivered to the provided block.
    #
    # The subscription automatically reconnects with exponential backoff on
    # transient failures. Use the returned {Subscription} or the
    # +cancellation_token+ to stop.
    #
    # @param subscription [PubSub::EventsSubscription] channel and group config
    # @param cancellation_token [CancellationToken, nil] token for cooperative
    #   cancellation (auto-created if nil)
    # @param on_error [Proc, nil] callback receiving {Error} on stream or
    #   callback failures
    # @yield [event] called for each received event on a background thread
    # @yieldparam event [PubSub::EventReceived] the received event
    #
    # @return [Subscription] handle to check status, cancel, or join
    #
    # @raise [ArgumentError] if no block is given
    # @raise [ValidationError] if the subscription channel is invalid
    # @raise [ClientClosedError] if the client has been closed
    #
    # @note Wildcard channels (containing +*+ or +>+) are supported for events.
    #
    # @example
    #   token = KubeMQ::CancellationToken.new
    #   sub_config = KubeMQ::PubSub::EventsSubscription.new(
    #     channel: "events.>", group: "workers"
    #   )
    #   subscription = client.subscribe_to_events(sub_config, cancellation_token: token) do |event|
    #     puts "#{event.channel}: #{event.body}"
    #   end
    #   # later...
    #   token.cancel
    #   subscription.wait(5)
    #
    # @see PubSub::EventsSubscription
    # @see PubSub::EventReceived
    # @see CancellationToken
    # @see Subscription
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- subscription with auto-reconnect loop
    def subscribe_to_events(subscription, cancellation_token: nil, on_error: nil, &block)
      raise ArgumentError, 'Block required for subscribe_to_events' unless block

      Validator.validate_channel!(subscription.channel, allow_wildcards: true)
      ensure_connected!

      cancellation_token ||= CancellationToken.new
      nil

      thread = Thread.new do
        @transport.register_subscription(Thread.current)
        Thread.current[:cancellation_token] = cancellation_token
        reconnect_attempts = 0
        begin
          loop do
            break if cancellation_token.cancelled?

            begin
              @transport.ensure_connected!
              proto_sub = Transport::Converter.subscribe_to_proto(subscription, @config.client_id)
              stream = @transport.kubemq_client.subscribe_to_events(proto_sub)
              Thread.current[:grpc_call] = stream
              reconnect_attempts = 0
              stream.each do |event_receive|
                break if cancellation_token.cancelled?

                hash = Transport::Converter.proto_to_event_received(event_receive)
                received = PubSub::EventReceived.new(**hash)
                begin
                  block.call(received)
                rescue StandardError => e
                  begin
                    on_error&.call(Error.new("Callback error: #{e.message}", code: ErrorCode::CALLBACK_ERROR))
                  rescue StandardError => nested
                    Kernel.warn("[kubemq] on_error callback raised: #{nested.message}")
                  end
                end
              end
            rescue CancellationError
              break
            rescue GRPC::BadStatus, StandardError => e
              @transport.on_disconnect! if e.is_a?(GRPC::Unavailable) || e.is_a?(GRPC::DeadlineExceeded)
              reconnect_attempts += 1
              begin
                if e.is_a?(GRPC::BadStatus)
                  on_error&.call(ErrorMapper.map_grpc_error(e, operation: 'subscribe_events'))
                else
                  on_error&.call(Error.new(e.message, code: ErrorCode::STREAM_BROKEN))
                end
              rescue StandardError => cb_err
                Kernel.warn("[kubemq] on_error callback raised: #{cb_err.message}")
              end
              delay = [@config.reconnect_policy.base_interval *
                (@config.reconnect_policy.multiplier**(reconnect_attempts - 1)),
                       @config.reconnect_policy.max_delay].min
              sleep(delay) unless cancellation_token.cancelled?
            end
          end
        rescue StandardError => e
          Thread.current[:kubemq_subscription]&.mark_error(e)
        ensure
          begin; Thread.current[:grpc_call]&.cancel; rescue StandardError; end
          Thread.current[:kubemq_subscription]&.mark_closed
          @transport.unregister_subscription(Thread.current)
        end
      end

      sub_wrapper = KubeMQ::Subscription.new(thread: thread, cancellation_token: cancellation_token)
      thread[:kubemq_subscription] = sub_wrapper
      sub_wrapper
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Sends a single event to a durable events store channel.
    #
    # Unlike {#send_event}, the broker persists events store messages and
    # supports replay via {#subscribe_to_events_store}.
    #
    # @param message [PubSub::EventStoreMessage] event store message to send
    #
    # @return [PubSub::EventStoreResult] send confirmation with error status
    #
    # @raise [ValidationError] if channel name or content is invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @example
    #   msg = KubeMQ::PubSub::EventStoreMessage.new(
    #     channel: "orders.created",
    #     body: '{"id": 42}'
    #   )
    #   result = client.send_event_store(msg)
    #   puts "Stored: #{result.id}" if result.sent
    #
    # @see PubSub::EventStoreMessage
    # @see PubSub::EventStoreResult
    def send_event_store(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      Validator.validate_content!(message.metadata, message.body)
      ensure_connected!

      proto = Transport::Converter.event_to_proto(message, @config.client_id, store: true)
      result = @transport.kubemq_client.send_event(proto)
      hash = Transport::Converter.proto_to_event_result(result)
      PubSub::EventStoreResult.new(**hash)
    end

    # Creates a streaming events store sender for high-throughput publishing
    # with synchronous per-message confirmation.
    #
    # Close the sender explicitly when finished, or it will be closed when
    # the client is closed.
    #
    # @return [PubSub::EventStoreSender] streaming sender bound to this client
    #
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see PubSub::EventStoreSender
    def create_events_store_sender
      ensure_connected!
      sender = PubSub::EventStoreSender.new(transport: @transport, client_id: @config.client_id)
      senders_mutex.synchronize { senders_list << sender }
      sender
    end

    # Subscribes to durable events store messages on a channel. Runs on a
    # background thread; incoming events are delivered to the provided block.
    #
    # The subscription automatically reconnects with exponential backoff on
    # transient failures. On reconnect, playback resumes from the last
    # received sequence number to avoid duplicates.
    #
    # @param subscription [PubSub::EventsStoreSubscription] channel, group,
    #   and start position config
    # @param cancellation_token [CancellationToken, nil] token for cooperative
    #   cancellation (auto-created if nil)
    # @param on_error [Proc, nil] callback receiving {Error} on stream or
    #   callback failures
    # @yield [event] called for each received event on a background thread
    # @yieldparam event [PubSub::EventStoreReceived] the received event
    #
    # @return [Subscription] handle to check status, cancel, or join
    #
    # @raise [ArgumentError] if no block is given
    # @raise [ValidationError] if the subscription channel or start position
    #   is invalid
    # @raise [ClientClosedError] if the client has been closed
    #
    # @note On reconnect the subscription automatically resumes from the last
    #   received sequence number, overriding the original start position.
    #
    # @example Subscribe from the beginning
    #   sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    #     channel: "orders",
    #     start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST
    #   )
    #   token = KubeMQ::CancellationToken.new
    #   client.subscribe_to_events_store(sub, cancellation_token: token) do |event|
    #     puts "seq=#{event.sequence}: #{event.body}"
    #   end
    #
    # @see PubSub::EventsStoreSubscription
    # @see PubSub::EventStoreReceived
    # @see PubSub::EventStoreStartPosition
    # @see CancellationToken
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- subscription with auto-reconnect + sequence tracking
    def subscribe_to_events_store(subscription, cancellation_token: nil, on_error: nil, &block)
      raise ArgumentError, 'Block required for subscribe_to_events_store' unless block

      Validator.validate_channel!(subscription.channel, allow_wildcards: false)
      Validator.validate_events_store_subscription!(
        subscription.start_position, subscription.start_position_value
      )
      ensure_connected!

      cancellation_token ||= CancellationToken.new
      nil

      thread = Thread.new do
        @transport.register_subscription(Thread.current)
        Thread.current[:cancellation_token] = cancellation_token
        last_sequence = 0
        reconnect_attempts = 0
        begin
          loop do
            break if cancellation_token.cancelled?

            begin
              @transport.ensure_connected!
              proto_sub = Transport::Converter.subscribe_to_proto(subscription, @config.client_id)
              if last_sequence.positive?
                proto_sub.EventsStoreTypeData = PubSub::EventStoreStartPosition::START_AT_SEQUENCE
                proto_sub.EventsStoreTypeValue = last_sequence + 1
              end
              stream = @transport.kubemq_client.subscribe_to_events(proto_sub)
              Thread.current[:grpc_call] = stream
              reconnect_attempts = 0
              stream.each do |event_receive|
                break if cancellation_token.cancelled?

                hash = Transport::Converter.proto_to_event_received(event_receive)
                received = PubSub::EventStoreReceived.new(**hash)
                last_sequence = received.sequence if received.sequence.positive?
                begin
                  block.call(received)
                rescue StandardError => e
                  begin
                    on_error&.call(Error.new("Callback error: #{e.message}", code: ErrorCode::CALLBACK_ERROR))
                  rescue StandardError => nested
                    Kernel.warn("[kubemq] on_error callback raised: #{nested.message}")
                  end
                end
              end
            rescue CancellationError
              break
            rescue GRPC::BadStatus, StandardError => e
              @transport.on_disconnect! if e.is_a?(GRPC::Unavailable) || e.is_a?(GRPC::DeadlineExceeded)
              reconnect_attempts += 1
              begin
                if e.is_a?(GRPC::BadStatus)
                  on_error&.call(ErrorMapper.map_grpc_error(e, operation: 'subscribe_events_store'))
                else
                  on_error&.call(Error.new(e.message, code: ErrorCode::STREAM_BROKEN))
                end
              rescue StandardError => cb_err
                Kernel.warn("[kubemq] on_error callback raised: #{cb_err.message}")
              end
              delay = [@config.reconnect_policy.base_interval *
                (@config.reconnect_policy.multiplier**(reconnect_attempts - 1)),
                       @config.reconnect_policy.max_delay].min
              sleep(delay) unless cancellation_token.cancelled?
            end
          end
        rescue StandardError => e
          Thread.current[:kubemq_subscription]&.mark_error(e)
        ensure
          begin; Thread.current[:grpc_call]&.cancel; rescue StandardError; end
          Thread.current[:kubemq_subscription]&.mark_closed
          @transport.unregister_subscription(Thread.current)
        end
      end

      sub_wrapper = KubeMQ::Subscription.new(thread: thread, cancellation_token: cancellation_token)
      thread[:kubemq_subscription] = sub_wrapper
      sub_wrapper
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Closes the client, all open senders, and releases resources.
    #
    # Closes any {PubSub::EventSender} or {PubSub::EventStoreSender}
    # instances created through this client before closing the transport.
    # This method is idempotent.
    #
    # @return [void]
    def close
      senders_mutex.synchronize do
        senders_list.each do |s|
          s.close
        rescue StandardError
          nil
        end
        senders_list.clear
      end
      super
    end

    # Creates an events channel on the broker.
    #
    # @param channel_name [String] name for the new channel
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#create_channel
    def create_events_channel(channel_name:)
      create_channel(channel_name: channel_name, channel_type: ChannelType::EVENTS)
    end

    # Creates an events store channel on the broker.
    #
    # @param channel_name [String] name for the new channel
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#create_channel
    def create_events_store_channel(channel_name:)
      create_channel(channel_name: channel_name, channel_type: ChannelType::EVENTS_STORE)
    end

    # Deletes an events channel from the broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#delete_channel
    def delete_events_channel(channel_name:)
      delete_channel(channel_name: channel_name, channel_type: ChannelType::EVENTS)
    end

    # Deletes an events store channel from the broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#delete_channel
    def delete_events_store_channel(channel_name:)
      delete_channel(channel_name: channel_name, channel_type: ChannelType::EVENTS_STORE)
    end

    # Lists events channels, with optional name filtering.
    #
    # @param search [String, nil] substring filter for channel names
    # @return [Array<ChannelInfo>] matching channels with metadata
    # @raise [ClientClosedError] if the client has been closed
    # @see BaseClient#list_channels
    def list_events_channels(search: nil)
      list_channels(channel_type: ChannelType::EVENTS, search: search)
    end

    # Lists events store channels, with optional name filtering.
    #
    # @param search [String, nil] substring filter for channel names
    # @return [Array<ChannelInfo>] matching channels with metadata
    # @raise [ClientClosedError] if the client has been closed
    # @see BaseClient#list_channels
    def list_events_store_channels(search: nil)
      list_channels(channel_type: ChannelType::EVENTS_STORE, search: search)
    end

    private

    def senders_list
      @senders_list ||= []
    end

    def senders_mutex
      @senders_mutex ||= Mutex.new
    end
  end
end
