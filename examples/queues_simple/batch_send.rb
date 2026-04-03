# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.batch'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-batch-example')
  puts "Connected to #{address}"

  messages = 5.times.map do |i|
    KubeMQ::Queues::QueueMessage.new(
      channel: channel,
      metadata: "batch-item-#{i}",
      body: "payload-#{i}"
    )
  end

  results = client.send_queue_messages_batch(messages)
  puts "Batch sent #{results.size} messages:"
  results.each_with_index do |r, i|
    puts "  [#{i}] id=#{r.id}, error?=#{r.error?}"
  end

  received = client.receive_queue_messages(channel: channel, max_messages: 10, wait_timeout_seconds: 5)
  puts "Received #{received.size} messages"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
