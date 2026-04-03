# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.delayed'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-delayed-example')
  puts "Connected to #{address}"

  policy = KubeMQ::Queues::QueueMessagePolicy.new(delay_seconds: 5)
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'delayed-order',
    body: 'process-after-delay',
    policy: policy
  )
  result = client.send_queue_message(msg)
  puts "Sent delayed message: id=#{result.id}, delayed_to=#{result.delayed_to}"

  puts 'Trying immediate receive (should get nothing)...'
  immediate = client.receive_queue_messages(channel: channel, max_messages: 1, wait_timeout_seconds: 2)
  puts "Immediate: #{immediate.size} messages"

  puts 'Waiting for delay to expire...'
  sleep 5

  received = client.receive_queue_messages(channel: channel, max_messages: 1, wait_timeout_seconds: 5)
  puts "After delay: #{received.size} message(s)"
  received.each { |m| puts "  #{m.metadata}: #{m.body}" }
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
