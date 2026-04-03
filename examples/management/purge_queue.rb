# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'mgmt.purge.test'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'mgmt-purge-example')
  puts "Connected to #{address}"

  5.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "item-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts "Sent 5 messages to #{channel}"

  before = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 2, peek: true)
  puts "Before purge: #{before.size} messages"

  client.purge_queue_channel(channel_name: channel)
  puts 'Queue purged'

  after = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 2, peek: true)
  puts "After purge: #{after.size} messages"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
