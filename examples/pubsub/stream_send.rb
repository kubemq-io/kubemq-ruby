# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'events.stream'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'stream-send-example')
  puts "Connected to #{address}"

  sender = client.create_events_sender
  puts 'Created stream sender'

  10.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(
      channel: channel,
      metadata: "stream event #{i}",
      body: "payload-#{i}"
    )
    sender.publish(msg)
    puts "Sent event #{i} via stream"
  end

  sleep 1
  puts 'All events sent via stream'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  sender&.close
  client&.close
  puts 'Done'
end
