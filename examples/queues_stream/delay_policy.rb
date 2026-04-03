# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.delay'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-delay-example')
  puts "Connected to #{address}"

  policy = KubeMQ::Queues::QueueMessagePolicy.new(delay_seconds: 3)
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'delayed-3s',
    body: 'process-later',
    policy: policy
  )
  result = client.send_queue_message(msg)
  puts "Sent message with delay=3s: id=#{result.id}"

  receiver = client.create_downstream_receiver
  request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 1, wait_timeout: 1)
  response = receiver.poll(request)
  puts "Immediate poll: #{response.messages.size} messages (should be 0)"

  puts 'Waiting for delay to expire...'
  sleep 4

  response2 = receiver.poll(request)
  puts "After delay: #{response2.messages.size} message(s)"
  response2.messages.each do |m|
    puts "  #{m.metadata}: #{m.body}"
    m.ack
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
