# frozen_string_literal: true

require_relative 'kubemq/version'
require_relative 'kubemq/error_codes'
require_relative 'kubemq/errors'
require_relative 'kubemq/errors/error_mapper'
require_relative 'kubemq/types'
require_relative 'kubemq/configuration'
require_relative 'kubemq/server_info'
require_relative 'kubemq/channel_info'
require_relative 'kubemq/telemetry/semconv'
require_relative 'kubemq/telemetry/otel'
require_relative 'kubemq/cancellation_token'
require_relative 'kubemq/subscription'
require_relative 'kubemq/validation/validator'
require_relative 'kubemq/transport/state_machine'
require_relative 'kubemq/transport/message_buffer'
require_relative 'kubemq/transport/reconnect_manager'
require_relative 'kubemq/transport/converter'
require_relative 'kubemq/interceptors/auth_interceptor'
require_relative 'kubemq/interceptors/metrics_interceptor'
require_relative 'kubemq/interceptors/retry_interceptor'
require_relative 'kubemq/interceptors/error_mapping_interceptor'
require_relative 'kubemq/transport/grpc_transport'
require_relative 'kubemq/transport/channel_manager'
require_relative 'kubemq/base_client'

# PubSub
require_relative 'kubemq/pubsub/event_message'
require_relative 'kubemq/pubsub/event_send_result'
require_relative 'kubemq/pubsub/event_received'
require_relative 'kubemq/pubsub/event_store_message'
require_relative 'kubemq/pubsub/event_store_result'
require_relative 'kubemq/pubsub/event_store_received'
require_relative 'kubemq/pubsub/events_subscription'
require_relative 'kubemq/pubsub/events_store_subscription'
require_relative 'kubemq/pubsub/event_sender'
require_relative 'kubemq/pubsub/event_store_sender'
require_relative 'kubemq/pubsub/client'

# Queues
require_relative 'kubemq/queues/queue_message'
require_relative 'kubemq/queues/queue_message_received'
require_relative 'kubemq/queues/queue_send_result'
require_relative 'kubemq/queues/queue_poll_request'
require_relative 'kubemq/queues/queue_poll_response'
require_relative 'kubemq/queues/upstream_sender'
require_relative 'kubemq/queues/downstream_receiver'
require_relative 'kubemq/queues/client'

# CQ (Commands + Queries)
require_relative 'kubemq/cq/command_message'
require_relative 'kubemq/cq/command_received'
require_relative 'kubemq/cq/command_response'
require_relative 'kubemq/cq/command_response_message'
require_relative 'kubemq/cq/commands_subscription'
require_relative 'kubemq/cq/query_message'
require_relative 'kubemq/cq/query_received'
require_relative 'kubemq/cq/query_response'
require_relative 'kubemq/cq/query_response_message'
require_relative 'kubemq/cq/queries_subscription'
require_relative 'kubemq/cq/client'

# KubeMQ Ruby SDK — official client library for KubeMQ message broker.
#
# Provides pub/sub events, durable events store, message queues (stream and
# simple APIs), and request/reply commands and queries over gRPC.
#
# Configure globally or pass options directly to client constructors.
#
# @example Global configuration
#   KubeMQ.configure do |c|
#     c.address = "kubemq.example.com:50000"
#     c.auth_token = ENV["KUBEMQ_AUTH_TOKEN"]
#   end
#
#   client = KubeMQ::PubSubClient.new
#
# @example Per-client configuration
#   client = KubeMQ::QueuesClient.new(address: "localhost:50000", client_id: "worker-1")
#
# @see KubeMQ::Configuration
# @see KubeMQ::PubSubClient
# @see KubeMQ::QueuesClient
# @see KubeMQ::CQClient
module KubeMQ
  # Yields the global {Configuration} instance for modification.
  #
  # Settings applied here act as defaults for any client created without
  # explicit constructor arguments. Constructor arguments take precedence.
  #
  # @yield [config] the global configuration instance
  # @yieldparam config [Configuration] mutable configuration object
  # @return [void]
  #
  # @example
  #   KubeMQ.configure do |c|
  #     c.address = "broker.example.com:50000"
  #     c.reconnect_policy.max_delay = 60.0
  #   end
  def self.configure
    yield(configuration)
  end

  # Returns the global {Configuration} singleton, creating it on first access.
  #
  # @return [Configuration] the current global configuration
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Resets the global configuration to a fresh {Configuration} with defaults.
  #
  # @return [Configuration] the new default configuration
  def self.reset_configuration!
    @configuration = Configuration.new
  end
end
