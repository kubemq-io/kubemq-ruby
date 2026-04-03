# frozen_string_literal: true

require 'securerandom'

module KubeMQ
  # Client for KubeMQ commands and queries — synchronous request/reply RPC.
  #
  # Commands are fire-and-confirm (no response body); queries return data and
  # support server-side caching. Inherits connection management and channel
  # CRUD from {BaseClient}.
  #
  # @example Send a command and handle the response
  #   client = KubeMQ::CQClient.new(address: "localhost:50000")
  #   cmd = KubeMQ::CQ::CommandMessage.new(
  #     channel: "commands.users",
  #     body: '{"action": "create"}',
  #     timeout: 5000
  #   )
  #   response = client.send_command(cmd)
  #   puts "Executed: #{response.executed}"
  #   client.close
  #
  # @see CQ::CommandMessage
  # @see CQ::QueryMessage
  # @see CQ::CommandsSubscription
  # @see CQ::QueriesSubscription
  class CQClient < BaseClient
    # --- Commands ---

    # Sends a command to a responder and waits for confirmation.
    #
    # @param message [CQ::CommandMessage] command to send
    #
    # @return [CQ::CommandResponse] execution confirmation
    #
    # @raise [ValidationError] if channel, content, or timeout is invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    # @raise [TimeoutError] if no responder replies within the timeout
    #
    # @note Timeout is in milliseconds.
    #
    # @example
    #   cmd = KubeMQ::CQ::CommandMessage.new(
    #     channel: "commands.orders",
    #     body: '{"action": "cancel", "id": 42}',
    #     timeout: 10_000
    #   )
    #   response = client.send_command(cmd)
    #   puts "Success" if response.executed
    #
    # @see CQ::CommandMessage
    # @see CQ::CommandResponse
    def send_command(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      Validator.validate_content!(message.metadata, message.body)
      Validator.validate_timeout!(message.timeout)
      ensure_connected!

      proto = Transport::Converter.request_to_proto(message, @config.client_id, RequestType::COMMAND)
      response = @transport.kubemq_client.send_request(proto)
      hash = Transport::Converter.proto_to_command_response(response)
      CQ::CommandResponse.new(**hash)
    end

    # Subscribes to incoming commands on a channel. Runs on a background
    # thread; incoming commands are delivered to the provided block.
    #
    # The block should process the command and send a response via
    # {#send_response}. The subscription auto-reconnects with exponential
    # backoff on transient failures.
    #
    # @param subscription [CQ::CommandsSubscription] channel and group config
    # @param cancellation_token [CancellationToken, nil] token for cooperative
    #   cancellation (auto-created if nil)
    # @param on_error [Proc, nil] callback receiving {Error} on stream or
    #   callback failures
    # @yield [command] called for each received command on a background thread
    # @yieldparam command [CQ::CommandReceived] the received command
    #
    # @return [Subscription] handle to check status, cancel, or join
    #
    # @raise [ArgumentError] if no block is given
    # @raise [ValidationError] if the subscription channel is invalid
    # @raise [ClientClosedError] if the client has been closed
    #
    # @note Wildcard channels are NOT supported for commands.
    #
    # @example
    #   token = KubeMQ::CancellationToken.new
    #   sub = KubeMQ::CQ::CommandsSubscription.new(channel: "commands.orders")
    #   client.subscribe_to_commands(sub, cancellation_token: token) do |cmd|
    #     # process and respond
    #     client.send_response(
    #       KubeMQ::CQ::CommandResponseMessage.new(
    #         request_id: cmd.id,
    #         reply_channel: cmd.reply_channel,
    #         executed: true
    #       )
    #     )
    #   end
    #
    # @see CQ::CommandsSubscription
    # @see CQ::CommandReceived
    # @see #send_response
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- subscription with auto-reconnect loop
    def subscribe_to_commands(subscription, cancellation_token: nil, on_error: nil, &block)
      raise ArgumentError, 'Block required for subscribe_to_commands' unless block

      Validator.validate_channel!(subscription.channel, allow_wildcards: false)
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
              stream = @transport.kubemq_client.subscribe_to_requests(proto_sub)
              Thread.current[:grpc_call] = stream
              reconnect_attempts = 0
              stream.each do |request|
                break if cancellation_token.cancelled?

                received = CQ::CommandReceived.new(
                  id: request.RequestID,
                  channel: request.Channel,
                  metadata: request.Metadata,
                  body: request.Body,
                  reply_channel: request.ReplyChannel,
                  tags: request.Tags.to_h,
                  timeout: request.Timeout,
                  client_id: request.ClientID
                )
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
                  on_error&.call(ErrorMapper.map_grpc_error(e, operation: 'subscribe_commands'))
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

    # Sends a response to a received command or query.
    #
    # Call this from within a {#subscribe_to_commands} or
    # {#subscribe_to_queries} block to reply to the sender.
    #
    # @param response [CQ::CommandResponseMessage, CQ::QueryResponseMessage]
    #   the response to send
    #
    # @return [void]
    #
    # @raise [ValidationError] if +request_id+ or +reply_channel+ is missing
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    #
    # @see CQ::CommandResponseMessage
    # @see CQ::QueryResponseMessage
    def send_response(response)
      Validator.validate_response!(response.request_id, response.reply_channel)
      ensure_connected!

      proto = Transport::Converter.response_message_to_proto(response, @config.client_id)
      @transport.kubemq_client.send_response(proto)
      nil
    end

    # --- Queries ---

    # Sends a query to a responder and waits for a data response.
    #
    # Queries support server-side caching via +cache_key+ and +cache_ttl+
    # on the {CQ::QueryMessage}.
    #
    # @param message [CQ::QueryMessage] query to send
    #
    # @return [CQ::QueryResponse] response with body, metadata, and cache_hit
    #
    # @raise [ValidationError] if channel, content, timeout, or cache params
    #   are invalid
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ConnectionError] if unable to reach the broker
    # @raise [TimeoutError] if no responder replies within the timeout
    #
    # @note Timeout is in milliseconds.
    #
    # @example
    #   query = KubeMQ::CQ::QueryMessage.new(
    #     channel: "queries.users",
    #     body: '{"user_id": 42}',
    #     timeout: 10_000,
    #     cache_key: "user-42",
    #     cache_ttl: 60_000
    #   )
    #   response = client.send_query(query)
    #   puts "Data: #{response.body} (cache_hit=#{response.cache_hit})"
    #
    # @see CQ::QueryMessage
    # @see CQ::QueryResponse
    def send_query(message)
      Validator.validate_channel!(message.channel, allow_wildcards: false)
      Validator.validate_content!(message.metadata, message.body)
      Validator.validate_timeout!(message.timeout)
      Validator.validate_cache!(message.cache_key, message.cache_ttl) if message.cache_key
      ensure_connected!

      proto = Transport::Converter.request_to_proto(message, @config.client_id, RequestType::QUERY)
      response = @transport.kubemq_client.send_request(proto)
      hash = Transport::Converter.proto_to_query_response(response)
      CQ::QueryResponse.new(**hash)
    end

    # Subscribes to incoming queries on a channel. Runs on a background
    # thread; incoming queries are delivered to the provided block.
    #
    # The block should process the query and send a response via
    # {#send_response}. The subscription auto-reconnects with exponential
    # backoff on transient failures.
    #
    # @param subscription [CQ::QueriesSubscription] channel and group config
    # @param cancellation_token [CancellationToken, nil] token for cooperative
    #   cancellation (auto-created if nil)
    # @param on_error [Proc, nil] callback receiving {Error} on stream or
    #   callback failures
    # @yield [query] called for each received query on a background thread
    # @yieldparam query [CQ::QueryReceived] the received query
    #
    # @return [Subscription] handle to check status, cancel, or join
    #
    # @raise [ArgumentError] if no block is given
    # @raise [ValidationError] if the subscription channel is invalid
    # @raise [ClientClosedError] if the client has been closed
    #
    # @note Wildcard channels are NOT supported for queries.
    #
    # @example
    #   token = KubeMQ::CancellationToken.new
    #   sub = KubeMQ::CQ::QueriesSubscription.new(channel: "queries.users")
    #   client.subscribe_to_queries(sub, cancellation_token: token) do |query|
    #     client.send_response(
    #       KubeMQ::CQ::QueryResponseMessage.new(
    #         request_id: query.id,
    #         reply_channel: query.reply_channel,
    #         body: '{"name": "Alice"}',
    #         executed: true
    #       )
    #     )
    #   end
    #
    # @see CQ::QueriesSubscription
    # @see CQ::QueryReceived
    # @see #send_response
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- subscription with auto-reconnect loop
    def subscribe_to_queries(subscription, cancellation_token: nil, on_error: nil, &block)
      raise ArgumentError, 'Block required for subscribe_to_queries' unless block

      Validator.validate_channel!(subscription.channel, allow_wildcards: false)
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
              stream = @transport.kubemq_client.subscribe_to_requests(proto_sub)
              Thread.current[:grpc_call] = stream
              reconnect_attempts = 0
              stream.each do |request|
                break if cancellation_token.cancelled?

                received = CQ::QueryReceived.new(
                  id: request.RequestID,
                  channel: request.Channel,
                  metadata: request.Metadata,
                  body: request.Body,
                  reply_channel: request.ReplyChannel,
                  tags: request.Tags.to_h,
                  timeout: request.Timeout,
                  client_id: request.ClientID
                )
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
                  on_error&.call(ErrorMapper.map_grpc_error(e, operation: 'subscribe_queries'))
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

    # --- Channel Management Convenience ---

    # Creates a commands channel on the broker.
    #
    # @param channel_name [String] name for the new channel
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#create_channel
    def create_commands_channel(channel_name:)
      create_channel(channel_name: channel_name, channel_type: ChannelType::COMMANDS)
    end

    # Creates a queries channel on the broker.
    #
    # @param channel_name [String] name for the new channel
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#create_channel
    def create_queries_channel(channel_name:)
      create_channel(channel_name: channel_name, channel_type: ChannelType::QUERIES)
    end

    # Deletes a commands channel from the broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#delete_channel
    def delete_commands_channel(channel_name:)
      delete_channel(channel_name: channel_name, channel_type: ChannelType::COMMANDS)
    end

    # Deletes a queries channel from the broker.
    #
    # @param channel_name [String] name of the channel to delete
    # @return [Boolean] +true+ on success
    # @raise [ClientClosedError] if the client has been closed
    # @raise [ChannelError] if the broker rejects the operation
    # @see BaseClient#delete_channel
    def delete_queries_channel(channel_name:)
      delete_channel(channel_name: channel_name, channel_type: ChannelType::QUERIES)
    end

    # Lists commands channels, with optional name filtering.
    #
    # @param search [String, nil] substring filter for channel names
    # @return [Array<ChannelInfo>] matching channels with metadata
    # @raise [ClientClosedError] if the client has been closed
    # @see BaseClient#list_channels
    def list_commands_channels(search: nil)
      list_channels(channel_type: ChannelType::COMMANDS, search: search)
    end

    # Lists queries channels, with optional name filtering.
    #
    # @param search [String, nil] substring filter for channel names
    # @return [Array<ChannelInfo>] matching channels with metadata
    # @raise [ClientClosedError] if the client has been closed
    # @see BaseClient#list_channels
    def list_queries_channels(search: nil)
      list_channels(channel_type: ChannelType::QUERIES, search: search)
    end
  end
end
