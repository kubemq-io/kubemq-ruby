# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'es.stream'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'es-stream-example')
  puts "Connected to #{address}"

  sender = client.create_events_store_sender
  puts 'Created events store stream sender'

  10.times do |i|
    msg = KubeMQ::PubSub::EventStoreMessage.new(
      channel: channel,
      metadata: "stream es event #{i}",
      body: "payload-#{i}"
    )
    result = sender.publish(msg)
    puts "Sent event #{i}: sent=#{result.sent}, id=#{result.id}"
  end

  puts 'All events sent via stream'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  sender&.close
  client&.close
  puts 'Done'
end
