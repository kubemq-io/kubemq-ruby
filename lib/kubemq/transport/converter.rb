# frozen_string_literal: true

require 'securerandom'
require_relative '../proto/kubemq_pb'

module KubeMQ
  module Transport
    # Bidirectional conversions between SDK domain objects and gRPC protobuf messages.
    #
    # All methods are module-level (+module_function+) and stateless. They handle
    # body encoding (binary-safe), tag validation, UUID generation for missing IDs,
    # and subscription type routing.
    #
    # @api private
    #
    # @see GrpcTransport
    # @see Validator
    # rubocop:disable Metrics/ModuleLength -- bidirectional proto mapping helpers
    module Converter
      module_function

      # Converts an SDK event message to a protobuf +Kubemq::Event+.
      #
      # @param message [PubSub::EventMessage, PubSub::EventStoreMessage] the outbound event
      # @param client_id [String] the client identifier
      # @param store [Boolean] +true+ for events store (durable), +false+ for fire-and-forget
      # @return [Kubemq::Event] protobuf event ready to send
      # @raise [ValidationError] if tag keys or values are not strings
      def event_to_proto(message, client_id, store: false)
        body = encode_body(message.body)
        tags = message.respond_to?(:tags) ? (message.tags || {}) : {}
        validate_tags!(tags)

        ::Kubemq::Event.new(
          EventID: message.id || SecureRandom.uuid,
          ClientID: client_id,
          Channel: message.channel,
          Metadata: message.metadata || '',
          Body: body,
          Store: store,
          Tags: tags
        )
      end

      # Extracts send result fields from a protobuf +Kubemq::Result+.
      #
      # @param result [Kubemq::Result] protobuf send result
      # @return [Hash{Symbol => Object}] +:id+, +:sent+, +:error+ fields
      def proto_to_event_result(result)
        {
          id: result.EventID,
          sent: result.Sent,
          error: result.Error.empty? ? nil : result.Error
        }
      end

      # Extracts received event fields from a protobuf +Kubemq::EventReceive+.
      #
      # @param event_receive [Kubemq::EventReceive] protobuf received event
      # @return [Hash{Symbol => Object}] +:id+, +:channel+, +:metadata+, +:body+,
      #   +:timestamp+, +:sequence+, +:tags+
      def proto_to_event_received(event_receive)
        {
          id: event_receive.EventID,
          channel: event_receive.Channel,
          metadata: event_receive.Metadata,
          body: event_receive.Body,
          timestamp: event_receive.Timestamp,
          sequence: event_receive.Sequence,
          tags: event_receive.Tags.to_h
        }
      end

      # Converts an SDK subscription object to a protobuf +Kubemq::Subscribe+.
      #
      # Routes to the correct +SubscribeTypeData+ based on {SubscribeType} and
      # populates events store start position fields when applicable.
      #
      # @param subscription [PubSub::EventsSubscription, PubSub::EventsStoreSubscription,
      #   CQ::CommandsSubscription, CQ::QueriesSubscription] the subscription config
      # @param client_id [String] the client identifier
      # @return [Kubemq::Subscribe] protobuf subscribe request
      # @raise [ArgumentError] if the subscribe type is unknown
      def subscribe_to_proto(subscription, client_id)
        sub = ::Kubemq::Subscribe.new(
          ClientID: client_id,
          Channel: subscription.channel,
          Group: subscription.respond_to?(:group) ? (subscription.group || '') : ''
        )

        case subscription.subscribe_type
        when SubscribeType::EVENTS
          sub.SubscribeTypeData = SubscribeType::EVENTS
        when SubscribeType::EVENTS_STORE
          sub.SubscribeTypeData = SubscribeType::EVENTS_STORE
          sub.EventsStoreTypeData = subscription.start_position || 0
          sub.EventsStoreTypeValue = subscription.start_position_value || 0
        when SubscribeType::COMMANDS
          sub.SubscribeTypeData = SubscribeType::COMMANDS
        when SubscribeType::QUERIES
          sub.SubscribeTypeData = SubscribeType::QUERIES
        else
          raise ArgumentError, "Unknown subscribe_type: #{subscription.subscribe_type.inspect}"
        end

        sub
      end

      # Converts an SDK queue message to a protobuf +Kubemq::QueueMessage+.
      #
      # Includes the optional delivery policy (expiration, delay, dead letter)
      # when present on the message.
      #
      # @param message [Queues::QueueMessage] the outbound queue message
      # @param client_id [String] the client identifier
      # @return [Kubemq::QueueMessage] protobuf queue message ready to send
      # @raise [ValidationError] if tag keys or values are not strings
      def queue_message_to_proto(message, client_id)
        body = encode_body(message.body)
        tags = message.respond_to?(:tags) ? (message.tags || {}) : {}
        validate_tags!(tags)

        msg = ::Kubemq::QueueMessage.new(
          MessageID: message.id || SecureRandom.uuid,
          ClientID: client_id,
          Channel: message.channel,
          Metadata: message.metadata || '',
          Body: body,
          Tags: tags
        )

        if message.respond_to?(:policy) && message.policy
          policy = message.policy
          msg.Policy = ::Kubemq::QueueMessagePolicy.new(
            ExpirationSeconds: policy.expiration_seconds || 0,
            DelaySeconds: policy.delay_seconds || 0,
            MaxReceiveCount: policy.max_receive_count || 0,
            MaxReceiveQueue: policy.max_receive_queue || ''
          )
        end

        msg
      end

      # Extracts received queue message fields from a protobuf +Kubemq::QueueMessage+.
      #
      # @param msg [Kubemq::QueueMessage] protobuf received queue message
      # @return [Hash{Symbol => Object}] +:id+, +:channel+, +:metadata+, +:body+,
      #   +:tags+, +:attributes+
      def proto_to_queue_message_received(msg)
        attrs = if msg.Attributes
                  {
                    timestamp: msg.Attributes.Timestamp,
                    sequence: msg.Attributes.Sequence,
                    md5_of_body: msg.Attributes.MD5OfBody,
                    receive_count: msg.Attributes.ReceiveCount,
                    re_routed: msg.Attributes.ReRouted,
                    re_routed_from_queue: msg.Attributes.ReRoutedFromQueue,
                    expiration_at: msg.Attributes.ExpirationAt,
                    delayed_to: msg.Attributes.DelayedTo
                  }
                end

        {
          id: msg.MessageID,
          channel: msg.Channel,
          metadata: msg.Metadata,
          body: msg.Body,
          tags: msg.Tags.to_h,
          attributes: attrs
        }
      end

      # Converts an SDK command or query message to a protobuf +Kubemq::Request+.
      #
      # @param message [CQ::CommandMessage, CQ::QueryMessage] the outbound request
      # @param client_id [String] the client identifier
      # @param type [Integer] one of {RequestType}::COMMAND or {RequestType}::QUERY
      # @return [Kubemq::Request] protobuf request ready to send
      # @raise [ValidationError] if tag keys or values are not strings
      def request_to_proto(message, client_id, type)
        body = encode_body(message.body)
        tags = message.respond_to?(:tags) ? (message.tags || {}) : {}
        validate_tags!(tags)

        ::Kubemq::Request.new(
          RequestID: message.id || SecureRandom.uuid,
          RequestTypeData: type,
          ClientID: client_id,
          Channel: message.channel,
          Metadata: message.metadata || '',
          Body: body,
          Timeout: message.timeout || 10_000,
          CacheKey: message.respond_to?(:cache_key) ? (message.cache_key || '') : '',
          CacheTTL: message.respond_to?(:cache_ttl) ? (message.cache_ttl || 0) : 0,
          Tags: tags
        )
      end

      # Extracts command response fields from a protobuf +Kubemq::Response+.
      #
      # @param response [Kubemq::Response] protobuf command response
      # @return [Hash{Symbol => Object}] +:client_id+, +:request_id+, +:executed+,
      #   +:timestamp+, +:error+, +:tags+
      def proto_to_command_response(response)
        {
          client_id: response.ClientID,
          request_id: response.RequestID,
          executed: response.Executed,
          timestamp: response.Timestamp,
          error: response.Error.empty? ? nil : response.Error,
          tags: response.Tags.to_h
        }
      end

      # Extracts query response fields from a protobuf +Kubemq::Response+.
      #
      # @param response [Kubemq::Response] protobuf query response
      # @return [Hash{Symbol => Object}] +:client_id+, +:request_id+, +:executed+,
      #   +:metadata+, +:body+, +:cache_hit+, +:timestamp+, +:error+, +:tags+
      def proto_to_query_response(response)
        {
          client_id: response.ClientID,
          request_id: response.RequestID,
          executed: response.Executed,
          metadata: response.Metadata,
          body: response.Body,
          cache_hit: response.CacheHit,
          timestamp: response.Timestamp,
          error: response.Error.empty? ? nil : response.Error,
          tags: response.Tags.to_h
        }
      end

      # Converts an SDK response message to a protobuf +Kubemq::Response+.
      #
      # @param response [CQ::CommandResponseMessage, CQ::QueryResponseMessage] the outbound response
      # @param client_id [String] the client identifier
      # @return [Kubemq::Response] protobuf response ready to send
      # @raise [ValidationError] if tag keys or values are not strings
      def response_message_to_proto(response, client_id)
        raw_body = response.respond_to?(:body) ? response.body : nil
        body = encode_body(raw_body)
        tags = response.respond_to?(:tags) ? (response.tags || {}) : {}
        validate_tags!(tags)

        ::Kubemq::Response.new(
          ClientID: client_id,
          RequestID: response.request_id,
          ReplyChannel: response.reply_channel,
          Metadata: response.respond_to?(:metadata) ? (response.metadata || '') : '',
          Body: body,
          Executed: response.respond_to?(:executed) ? response.executed : true,
          Error: response.respond_to?(:error) ? (response.error || '') : '',
          Tags: tags
        )
      end

      # Validates that all tag keys and values are strings.
      #
      # @param tags [Hash, nil] key-value tag map to validate
      # @return [void]
      # @raise [ValidationError] if any key or value is not a +String+
      def validate_tags!(tags)
        return if tags.nil?

        tags.each do |k, v|
          raise ValidationError, "Tag key must be String, got #{k.class}" unless k.is_a?(String)
          raise ValidationError, "Tag value must be String, got #{v.class} for key '#{k}'" unless v.is_a?(String)
        end
      end

      # Encodes a message body to binary (ASCII-8BIT).
      #
      # @param body [String, nil] the message body to encode
      # @return [String] binary-encoded body (empty binary string if nil)
      # @raise [ArgumentError] if +body+ is not a +String+ or +nil+
      def encode_body(body)
        return ''.b if body.nil?
        raise ArgumentError, "body must be a String, got #{body.class}" unless body.is_a?(String)

        body.dup.force_encoding('ASCII-8BIT')
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
