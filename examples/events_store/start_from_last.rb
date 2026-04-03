# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.from-last'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-last-example')
  puts "Connected to #{address}"

  3.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "stored #{i}", body: "data-#{i}")
    client.send_event_store(msg)
  end
  puts 'Pre-stored 3 events'
  sleep 1

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_LAST
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received (from last): #{event.metadata}"
  end
  puts 'Subscribed with START_FROM_LAST — only the last stored + new events'

  msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: 'new after sub', body: 'new')
  client.send_event_store(msg)

  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
