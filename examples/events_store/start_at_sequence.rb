# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.at-sequence'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-seq-example')
  puts "Connected to #{address}"

  5.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(channel: channel, metadata: "event #{i}", body: "data-#{i}")
    client.send_event_store(msg)
  end
  puts 'Pre-stored 5 events'
  sleep 1

  cancel = KubeMQ::CancellationToken.new
  resume_sequence = 3

  sub = KubeMQ::PubSub::EventsStoreSubscription.new(
    channel: channel,
    start_position: KubeMQ::PubSub::EventStoreStartPosition::START_AT_SEQUENCE,
    start_position_value: resume_sequence
  )
  client.subscribe_to_events_store(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Received (from seq #{resume_sequence}): #{event.metadata}"
  end
  puts "Subscribed with START_AT_SEQUENCE=#{resume_sequence}"

  sleep 3
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
