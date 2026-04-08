# frozen_string_literal: true

# Example: Graceful Shutdown
# Expected output:
#   Connected to localhost:50000
#   Subscription active, sending events...
#   Received: shutdown-msg-0
#   Received: shutdown-msg-1
#   Cancelling subscription...
#   Subscription cancelled
#   Client closed — shutdown complete
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'error_handling.shutdown'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'shutdown-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
  thread = client.subscribe_to_events(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
    puts "Received: #{event.metadata}"
  end
  sleep 1

  puts 'Subscription active, sending events...'
  2.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: "shutdown-msg-#{i}", body: "data-#{i}")
    client.send_event(msg)
    sleep 0.2
  end
  sleep 1

  # Graceful shutdown sequence
  puts 'Cancelling subscription...'
  cancel.cancel
  thread.join(3)
  puts 'Subscription cancelled'

  client.close
  puts 'Client closed — shutdown complete'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  puts 'Done'
end
