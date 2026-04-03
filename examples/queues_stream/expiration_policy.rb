# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.expiration'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-expire-example')
  puts "Connected to #{address}"

  policy = KubeMQ::Queues::QueueMessagePolicy.new(expiration_seconds: 3)
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'expires-in-3s',
    body: 'ephemeral-data',
    policy: policy
  )
  result = client.send_queue_message(msg)
  puts "Sent message with expiration=3s: id=#{result.id}"

  receiver = client.create_downstream_receiver
  request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 1, wait_timeout: 1)
  response = receiver.poll(request)
  puts "Immediate poll: #{response.messages.size} messages"
  response.messages.each(&:ack)

  puts 'Waiting for expiration...'
  sleep 4

  response2 = receiver.poll(request)
  puts "After expiration: #{response2.messages.size} messages (should be 0)"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
