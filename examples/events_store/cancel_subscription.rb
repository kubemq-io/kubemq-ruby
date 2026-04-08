# frozen_string_literal: true

# Example: Cancel an Events Store Subscription
# Expected output:
#   Connected to localhost:50000
#   Received: seq=1, body=before-cancel
#   Cancelling subscription...
#   Subscription cancelled
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.cancel'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-cancel-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST
  )
  thread = client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received: seq=#{event.sequence}, body=#{event.body}"
  end
  sleep 1

  msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: 'test', body: 'before-cancel')
  client.send_event_store(msg)
  sleep 1

  puts 'Cancelling subscription...'
  cancel.cancel
  thread.join(3)
  puts 'Subscription cancelled'

  # Event sent after cancel should not be received
  msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: 'test', body: 'after-cancel')
  client.send_event_store(msg)
  sleep 1
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
