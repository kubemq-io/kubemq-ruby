# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.group'
group = 'es-workers'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-group-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub1 = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY,
    group: group
  )
  client.subscribe_to_events_store(sub1, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Worker-1: #{event.metadata}"
  end

  sub2 = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY,
    group: group
  )
  client.subscribe_to_events_store(sub2, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Worker-2: #{event.metadata}"
  end
  sleep 1

  5.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "es event #{i}", body: "data-#{i}")
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
