# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.requeue-src'
requeue_channel = 'queues.stream.requeue-dst'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-requeue-example')
  puts "Connected to #{address}"

  3.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "item-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts "Pre-sent 3 messages to #{channel}"

  receiver = client.create_downstream_receiver
  request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 5, wait_timeout: 5)
  response = receiver.poll(request)

  if response.error?
    puts "Poll error: #{response.error}"
  else
    puts "Polled #{response.messages.size} messages — requeuing all to #{requeue_channel}"
    response.requeue_all(channel: requeue_channel)
    puts 'All messages requeued'
  end

  dest = client.receive_queue_messages(channel: requeue_channel, max_messages: 10, wait_timeout_seconds: 3)
  puts "Destination queue has #{dest.size} messages"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
