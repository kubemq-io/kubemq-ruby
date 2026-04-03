# frozen_string_literal: true

module KubeMQ
  module Telemetry
    # OpenTelemetry messaging semantic convention constants.
    #
    # Provides stable attribute names and span-kind symbols aligned with the
    # OpenTelemetry Semantic Conventions for Messaging (semconv v1.27+).
    # Used by {Telemetry.with_span} and {Interceptors::MetricsInterceptor}
    # to emit consistent telemetry data.
    #
    # @see Telemetry.with_span
    # @see Interceptors::MetricsInterceptor
    module SemanticConventions
      # Value for the +messaging.system+ attribute when talking to KubeMQ.
      MESSAGING_SYSTEM = 'kubemq'

      # @!group Attribute Keys

      # Identifies the messaging system (always {MESSAGING_SYSTEM} for KubeMQ).
      ATTR_MESSAGING_SYSTEM = 'messaging.system'

      # Name of the messaging operation (e.g., +"send"+, +"receive"+, +"process"+).
      ATTR_MESSAGING_OPERATION_NAME = 'messaging.operation.name'

      # Logical name of the destination channel or queue.
      ATTR_MESSAGING_DESTINATION_NAME = 'messaging.destination.name'

      # Unique identifier of the message being traced.
      ATTR_MESSAGING_MESSAGE_ID = 'messaging.message.id'

      # Identifier of the client that produced or consumed the message.
      ATTR_MESSAGING_CLIENT_ID = 'messaging.client.id'

      # @!endgroup

      # @!group Span Kinds

      # Span kind for message-producing operations (e.g., send, publish).
      SPAN_KIND_PRODUCER = :producer

      # Span kind for message-consuming operations (e.g., subscribe, poll).
      SPAN_KIND_CONSUMER = :consumer

      # Span kind for synchronous client operations (e.g., ping, create_channel).
      SPAN_KIND_CLIENT = :client

      # @!endgroup
    end
  end
end
