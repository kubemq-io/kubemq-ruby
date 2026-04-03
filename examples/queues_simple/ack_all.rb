# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.ackall'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-ackall-example')
  puts "Connected to #{address}"

  5.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "item-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts 'Sent 5 messages'

  affected = client.ack_all_queue_messages(channel: channel, wait_timeout_seconds: 5)
  puts "Acknowledged #{affected} messages"

  remaining = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 2)
  puts "Remaining messages: #{remaining.size}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
