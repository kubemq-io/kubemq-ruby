# frozen_string_literal: true

# Example: Multiple Subscribers (fan-out without consumer group)
# Expected output:
#   Connected to localhost:50000
#   Subscriber-1 received: broadcast event
#   Subscriber-2 received: broadcast event
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'events.multi_sub'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'multi-sub-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  # Two subscribers without a group -- both receive each event
  sub1 = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
  client.subscribe_to_events(sub1, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
    puts "Subscriber-1 received: #{event.metadata}"
  end

  sub2 = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
  client.subscribe_to_events(sub2, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
    puts "Subscriber-2 received: #{event.metadata}"
  end
  sleep 1

  msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: 'broadcast event', body: 'data')
  client.send_event(msg)

  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
