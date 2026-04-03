# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.dlq-src'
dlq_channel = 'queues.stream.dlq-dead'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-dlq-example')
  puts "Connected to #{address}"

  policy = KubeMQ::Queues::QueueMessagePolicy.new(max_receive_count: 2, max_receive_queue: dlq_channel)
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'fragile-message',
    body: 'may-fail',
    policy: policy
  )
  client.send_queue_message(msg)
  puts "Sent message with max_receive_count=2, DLQ=#{dlq_channel}"

  receiver = client.create_downstream_receiver

  2.times do |attempt|
    request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 1, wait_timeout: 3)
    response = receiver.poll(request)
    puts "Attempt #{attempt + 1}: #{response.messages.size} messages"
    response.nack_all if response.messages.any?
  end

  sleep 1
  dlq_request = KubeMQ::Queues::QueuePollRequest.new(channel: dlq_channel, max_items: 1, wait_timeout: 3)
  dlq_response = receiver.poll(dlq_request)
  puts "DLQ messages: #{dlq_response.messages.size}"
  dlq_response.messages.each do |m|
    puts "  DLQ: #{m.metadata}"
    m.ack
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
