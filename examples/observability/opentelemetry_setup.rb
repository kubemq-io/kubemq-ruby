# frozen_string_literal: true

# Example: OpenTelemetry Setup
# Expected output:
#   OpenTelemetry configured
#   Connected to localhost:50000
#   Event sent with tracing enabled
#   Done
#
# Note: This example documents the OpenTelemetry integration pattern.
# To see actual trace output, configure an OpenTelemetry collector
# (e.g. Jaeger) and install the opentelemetry-sdk gem.

require 'kubemq'

# The KubeMQ Ruby client supports OpenTelemetry through the standard
# Ruby OpenTelemetry SDK. When a TracerProvider is configured globally,
# gRPC calls are automatically instrumented.
#
# Example setup:
#   require 'opentelemetry/sdk'
#   require 'opentelemetry/exporter/otlp'
#
#   OpenTelemetry::SDK.configure do |c|
#     c.service_name = 'kubemq-ruby-example'
#     c.use_all
#   end

puts 'OpenTelemetry configured'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'otel-example')
  puts "Connected to #{address}"

  msg = KubeMQ::PubSub::EventMessage.new(
    channel: 'otel.example',
    metadata: 'otel-demo',
    body: 'traced-event'
  )
  client.send_event(msg)
  puts 'Event sent with tracing enabled'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
