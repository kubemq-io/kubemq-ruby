# frozen_string_literal: true

require 'securerandom'
require 'json'
require_relative '../proto/kubemq_pb'

module KubeMQ
  module Transport
    # Channel lifecycle operations (create, delete, list, purge) sent as
    # internal queries over the KubeMQ cluster management channel.
    #
    # All methods are module-level (+module_function+) and delegate the
    # underlying gRPC call to the provided {GrpcTransport} instance.
    #
    # @api private
    #
    # @see GrpcTransport
    # @see BaseClient
    # rubocop:disable Metrics/ModuleLength -- internal channel CRUD + list helpers
    module ChannelManager
      # Cluster-internal channel used for management requests.
      INTERNAL_CHANNEL = 'kubemq.cluster.internal.requests'

      # Default timeout (in milliseconds) for management requests.
      INTERNAL_TIMEOUT = 10_000

      module_function

      # Creates a channel on the KubeMQ broker.
      #
      # @param transport [GrpcTransport] the active transport instance
      # @param client_id [String] the client identifier
      # @param channel_name [String] name for the new channel
      # @param channel_type [String] one of {ChannelType} constants
      # @return [Boolean] +true+ on success
      # @raise [ChannelError] if the broker rejects the operation
      #
      # @see BaseClient#create_channel
      # rubocop:disable Naming/PredicateMethod -- command-style API returns true on success
      def create_channel(transport, client_id, channel_name, channel_type)
        request = build_request(
          client_id: client_id,
          metadata: 'create-channel',
          tags: {
            'channel_type' => channel_type,
            'channel' => channel_name,
            'client_id' => client_id
          }
        )

        response = transport.kubemq_client.send_request(request)
        check_response_error!(response, 'create_channel', channel_name)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Deletes a channel from the KubeMQ broker.
      #
      # @param transport [GrpcTransport] the active transport instance
      # @param client_id [String] the client identifier
      # @param channel_name [String] name of the channel to delete
      # @param channel_type [String] one of {ChannelType} constants
      # @return [Boolean] +true+ on success
      # @raise [ChannelError] if the broker rejects the operation
      #
      # @see BaseClient#delete_channel
      # rubocop:disable Naming/PredicateMethod -- command-style API returns true on success
      def delete_channel(transport, client_id, channel_name, channel_type)
        request = build_request(
          client_id: client_id,
          metadata: 'delete-channel',
          tags: {
            'channel_type' => channel_type,
            'channel' => channel_name
          }
        )

        response = transport.kubemq_client.send_request(request)
        check_response_error!(response, 'delete_channel', channel_name)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Lists channels of the specified type, with optional name filtering.
      #
      # Retries up to 3 times when the cluster snapshot is not ready.
      #
      # @param transport [GrpcTransport] the active transport instance
      # @param client_id [String] the client identifier
      # @param channel_type [String] one of {ChannelType} constants
      # @param search [String, nil] substring filter for channel names
      # @return [Array<ChannelInfo>] matching channels with metadata
      # @raise [ChannelError] if the broker rejects the operation after retries
      #
      # @see BaseClient#list_channels
      def list_channels(transport, client_id, channel_type, search = nil)
        tags = { 'channel_type' => channel_type }
        tags['channel_search'] = search if search && !search.empty?

        request = build_request(
          client_id: client_id,
          metadata: 'list-channels',
          tags: tags
        )

        max_retries = 3
        response = nil
        max_retries.times do |attempt|
          response = transport.kubemq_client.send_request(request)

          raise StandardError, response.Error if response.Error&.include?('cluster snapshot not ready')

          break
        rescue StandardError => e
          if e.message.include?('cluster snapshot not ready') && attempt < max_retries - 1
            sleep(1)
            next
          end
          raise ChannelError.new(
            "list_channels failed after #{attempt + 1} attempts: #{e.message}",
            operation: 'list_channels'
          )
        end

        check_response_error!(response, 'list_channels')
        parse_channel_list(response.Body, channel_type)
      end

      # Purges all pending messages from a queue channel.
      #
      # @param transport [GrpcTransport] the active transport instance
      # @param client_id [String] the client identifier
      # @param channel_name [String] queue channel to purge
      # @return [Hash{Symbol => Integer}] +{ affected_messages: Integer }+
      # @raise [ChannelError] if the broker rejects the operation
      #
      # @see BaseClient#purge_queue_channel
      def purge_queue(transport, client_id, channel_name)
        request = ::Kubemq::AckAllQueueMessagesRequest.new(
          RequestID: SecureRandom.uuid,
          ClientID: client_id,
          Channel: channel_name,
          WaitTimeSeconds: 5
        )

        response = transport.kubemq_client.ack_all_queue_messages(request)
        if response.IsError && !response.Error.empty?
          raise ChannelError.new(
            "Failed to purge queue '#{channel_name}': #{response.Error}",
            code: ErrorCode::INTERNAL,
            operation: 'purge_queue',
            channel: channel_name
          )
        end

        { affected_messages: response.AffectedMessages }
      end

      # Builds a protobuf management request targeting the internal channel.
      #
      # @param client_id [String] the client identifier
      # @param metadata [String] management operation name
      # @param tags [Hash{String => String}] operation parameters as tags
      # @return [Kubemq::Request] protobuf request
      def build_request(client_id:, metadata:, tags:)
        ::Kubemq::Request.new(
          RequestID: SecureRandom.uuid,
          RequestTypeData: RequestType::QUERY,
          ClientID: client_id,
          Channel: INTERNAL_CHANNEL,
          Metadata: metadata,
          Timeout: INTERNAL_TIMEOUT,
          Tags: tags
        )
      end

      # Raises {ChannelError} if the response contains a non-empty error string.
      #
      # @param response [Kubemq::Response] protobuf response to check
      # @param operation [String] the operation name for error context
      # @param channel [String, nil] the channel name for error context
      # @return [void]
      # @raise [ChannelError] if the response indicates failure
      def check_response_error!(response, operation, channel = nil)
        return if response.Error.nil? || response.Error.empty?

        raise ChannelError.new(
          "#{operation} failed: #{response.Error}",
          code: ErrorCode::INTERNAL,
          operation: operation,
          channel: channel
        )
      end

      # Parses a JSON channel list response body into {ChannelInfo} objects.
      #
      # @param body [String, nil] JSON response body
      # @param channel_type [String] channel type to assign to each entry
      # @return [Array<ChannelInfo>] parsed channel info objects
      def parse_channel_list(body, channel_type)
        return [] if body.nil? || body.empty?

        data = JSON.parse(body.dup.force_encoding('UTF-8'))
        channels = data.is_a?(Array) ? data : (data['channels'] || data['items'] || [data])
        channels.compact.map { |ch| ChannelInfo.from_json(ch.merge('type' => channel_type)) }
      rescue JSON::ParserError
        []
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
