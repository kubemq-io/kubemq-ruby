# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'events.group'
group = 'worker-group'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'group-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub1 = KubeMQ::PubSub::EventsSubscription.new(channel: channel, group: group)
  client.subscribe_to_events(sub1, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Worker-1 received: #{event.metadata}"
  end

  sub2 = KubeMQ::PubSub::EventsSubscription.new(channel: channel, group: group)
  client.subscribe_to_events(sub2, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    puts "Worker-2 received: #{event.metadata}"
  end
  sleep 1

  5.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: "event #{i}", body: "data-#{i}")
    client.send_event(msg)
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
