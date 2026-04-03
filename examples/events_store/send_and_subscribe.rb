# frozen_string_literal: true

# Example: Send and Subscribe to Events Store (durable events with replay)
# Expected output:
#   Connected to localhost:50000
#   Sent event 0: sent=true
#   Sent event 1: sent=true
#   Sent event 2: sent=true
#   Received: channel=es.basic, metadata=es event 0, body=payload-0
#   Received: channel=es.basic, metadata=es event 1, body=payload-1
#   Received: channel=es.basic, metadata=es event 2, body=payload-2
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.basic'

begin
  # Step 2: Create a PubSubClient connected to the broker
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-basic-example')
  puts "Connected to #{address}"

  # Step 3: Create a cancellation token for the subscription
  cancel = KubeMQ::CancellationToken.new

  # Step 4: Subscribe to events store with START_NEW_ONLY replay policy
  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received: channel=#{event.channel}, metadata=#{event.metadata}, body=#{event.body}"
  end
  sleep 1

  # Step 5: Send 3 durable events (each confirmed by the broker)
  3.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(
      channel: channel,
      metadata: "es event #{i}",
      body: "payload-#{i}"
    )
    result = client.send_event_store(msg)
    puts "Sent event #{i}: sent=#{result.sent}"
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
