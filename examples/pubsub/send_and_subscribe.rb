# frozen_string_literal: true

# Example: Send and Subscribe to Events
# Expected output:
#   Connected to localhost:50000
#   Sent event 0
#   Sent event 1
#   Sent event 2
#   Received: channel=events.example, metadata=event 0, body=payload-0
#   Received: channel=events.example, metadata=event 1, body=payload-1
#   Received: channel=events.example, metadata=event 2, body=payload-2
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'events.example'

begin
  # Step 2: Create a PubSubClient connected to the broker
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'pubsub-example')
  puts "Connected to #{address}"

  # Step 3: Create a cancellation token to stop the subscription later
  cancel = KubeMQ::CancellationToken.new

  # Step 4: Subscribe to events on the channel with an error handler
  sub = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
  client.subscribe_to_events(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
    puts "Received: channel=#{event.channel}, metadata=#{event.metadata}, body=#{event.body}"
  end
  sleep 1

  # Step 5: Send 3 events to the channel
  3.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(
      channel: channel,
      metadata: "event #{i}",
      body: "payload-#{i}"
    )
    client.send_event(msg)
    puts "Sent event #{i}"
  end

  # Step 6: Wait for events to be delivered
  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 7: Cancel the subscription and close the client
  cancel&.cancel
  client&.close
  puts 'Done'
end
