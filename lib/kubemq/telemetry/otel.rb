# frozen_string_literal: true

require_relative 'semconv'

module KubeMQ
  # OpenTelemetry integration for distributed tracing of KubeMQ operations.
  #
  # Provides a thin wrapper around the OpenTelemetry API that degrades
  # gracefully when the SDK is not loaded. Attribute names follow the
  # {SemanticConventions} module.
  #
  # @see SemanticConventions
  # @see Interceptors::MetricsInterceptor
  module Telemetry
    # OpenTelemetry tracer name registered for this SDK.
    TRACER_NAME = 'kubemq-ruby'

    # Returns whether the OpenTelemetry API is loaded and configured.
    #
    # @return [Boolean] +true+ if +OpenTelemetry.tracer_provider+ is available
    def self.otel_available?
      defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider)
    end

    # Runs +block+ inside an OpenTelemetry span when the API is loaded;
    # otherwise yields +nil+ once.
    #
    # Always sets +messaging.system+ to {SemanticConventions::MESSAGING_SYSTEM}.
    # Additional attributes are merged and their keys are coerced to strings.
    #
    # @param name [String] descriptive span name (e.g., +"kubemq send_event orders"+)
    # @param kind [Symbol] OpenTelemetry span kind -- +:producer+, +:consumer+,
    #   or +:client+ (default: {SemanticConventions::SPAN_KIND_CLIENT})
    # @param attributes [Hash{String, Symbol => String, Numeric, Boolean}]
    #   extra span attributes
    # @yield [span] the block to execute inside the span
    # @yieldparam span [OpenTelemetry::Trace::Span, nil] the active span,
    #   or +nil+ when OpenTelemetry is not available
    # @return [Object] the return value of the block
    # @raise [ArgumentError] if no block is given
    def self.with_span(name, kind: SemanticConventions::SPAN_KIND_CLIENT, attributes: {}, &block)
      raise ArgumentError, 'block required' unless block

      return block.call(nil) unless otel_available?

      merged = {
        SemanticConventions::ATTR_MESSAGING_SYSTEM => SemanticConventions::MESSAGING_SYSTEM
      }.merge(stringify_attributes(attributes))

      tracer = OpenTelemetry.tracer_provider.tracer(TRACER_NAME)
      tracer.in_span(name, attributes: merged, kind: kind, &block)
    end

    # Coerces attribute keys to strings.
    #
    # @param attributes [Hash] raw attribute map
    # @return [Hash{String => Object}] attributes with string keys
    def self.stringify_attributes(attributes)
      attributes.to_h.transform_keys(&:to_s)
    end

    private_class_method :stringify_attributes
  end
end
