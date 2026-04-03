# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'events.cancel'

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'cancel-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new
  received = 0

  sub = KubeMQ::PubSub::EventsSubscription.new(channel: channel)
  thread = client.subscribe_to_events(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |event|
    received += 1
    puts "Received ##{received}: #{event.metadata}"
  end
  sleep 1

  3.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: "event #{i}", body: 'data')
    client.send_event(msg)
  end
  sleep 1

  puts 'Cancelling subscription...'
  cancel.cancel
  thread.join(3)

  puts "Subscription cancelled. Received #{received} events total."
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
