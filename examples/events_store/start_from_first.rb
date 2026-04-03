# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.from-first'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-first-example')
  puts "Connected to #{address}"

  3.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "stored #{i}", body: "data-#{i}")
    client.send_event_store(msg)
    puts "Pre-stored event #{i}"
  end
  sleep 1

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Replayed: #{event.metadata}"
  end
  puts 'Subscribed with START_FROM_FIRST — replaying all stored events'

  sleep 3
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
