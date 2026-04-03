# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.new-only'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-new-only-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received new event: #{event.metadata}"
  end
  puts 'Subscribed with START_NEW_ONLY — only future events will arrive'
  sleep 1

  3.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "new event #{i}", body: "data-#{i}")
    client.send_event_store(msg)
    puts "Sent event #{i}"
  end

  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
