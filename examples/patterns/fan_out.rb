# frozen_string_literal: true

# Example: Fan-Out Pattern
# Expected output:
#   Connected to localhost:50000
#   Service-A received: system-update
#   Service-B received: system-update
#   Service-C received: system-update
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'patterns.fan_out'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'fan-out-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  # Three subscribers without a group -- all receive each event
  %w[Service-A Service-B Service-C].each do |name|
    sub = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
    client.subscribe_to_events(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
      puts "#{name} received: #{event.metadata}"
    end
  end
  sleep 1

  msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: 'system-update', body: 'update-data')
  client.send_event(msg)

  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
