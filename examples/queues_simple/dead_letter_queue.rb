# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.dlq-source'
dlq_channel = 'queues.simple.dlq-dead'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-dlq-example')
  puts "Connected to #{address}"

  policy = KubeMQ::Queues::QueueMessagePolicy.new(max_receive_count: 2, max_receive_queue: dlq_channel)
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'fragile-message',
    body: 'may-fail-processing',
    policy: policy
  )
  client.send_queue_message(msg)
  puts "Sent message with max_receive_count=2, DLQ=#{dlq_channel}"

  2.times do |attempt|
    received = client.receive_queue_messages(channel: channel, max_messages: 1, wait_timeout_seconds: 3)
    puts "Attempt #{attempt + 1}: received #{received.size} message(s) from source"
  end

  sleep 1
  dlq_msgs = client.receive_queue_messages(channel: dlq_channel, max_messages: 1, wait_timeout_seconds: 3)
  puts "DLQ messages: #{dlq_msgs.size}"
  dlq_msgs.each { |m| puts "  DLQ: #{m.metadata}" }
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
