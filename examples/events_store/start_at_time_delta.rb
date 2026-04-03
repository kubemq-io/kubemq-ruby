# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.at-delta'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-delta-example')
  puts "Connected to #{address}"

  3.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "event #{i}", body: "data-#{i}")
    client.send_event_store(msg)
  end
  puts 'Pre-stored 3 events'
  sleep 1

  cancel = KubeMQ::CancellationToken.new
  delta_seconds = 60

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_AT_TIME_DELTA,
    start_position_value: delta_seconds
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received (delta #{delta_seconds}s): #{event.metadata}"
  end
  puts "Subscribed with START_AT_TIME_DELTA=#{delta_seconds}s"

  sleep 3
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
