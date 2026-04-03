# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.peek'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-peek-example')
  puts "Connected to #{address}"

  3.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "item-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts 'Sent 3 messages'

  peeked = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 5, peek: true)
  puts "Peeked #{peeked.size} messages (not consumed):"
  peeked.each { |m| puts "  #{m.metadata}: #{m.body}" }

  received = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 5)
  puts "Received #{received.size} messages (consumed — same messages still available)"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
