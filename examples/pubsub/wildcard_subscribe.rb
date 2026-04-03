# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'wildcard-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'events.wildcard.*')
  client.subscribe_to_events(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |event|
    puts "Received on #{event.channel}: #{event.metadata}"
  end
  sleep 1

  %w[events.wildcard.a events.wildcard.b events.wildcard.c].each do |ch|
    msg = KubeMQ::PubSub::EventMessage.new(channel: ch, metadata: "hello from #{ch}", body: 'data')
    client.send_event(msg)
    puts "Sent to #{ch}"
  end

  sleep 2
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
