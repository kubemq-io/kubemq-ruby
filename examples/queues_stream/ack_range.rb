# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.ackrange'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-ackrange-example')
  puts "Connected to #{address}"

  5.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "item-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts 'Pre-sent 5 messages'

  receiver = client.create_downstream_receiver
  request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 5, wait_timeout: 5)
  response = receiver.poll(request)

  if response.error?
    puts "Poll error: #{response.error}"
  else
    puts "Polled #{response.messages.size} messages"
    sequences = response.messages.first(3).map { |m| m.instance_variable_get(:@sequence) }
    puts "Acking range: #{sequences.inspect}"
    response.ack_range(sequence_range: sequences)
    puts 'Ack range complete'
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
