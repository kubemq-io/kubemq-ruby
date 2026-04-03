# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.poll'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-poll-example')
  puts "Connected to #{address}"

  msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: 'poll-item', body: 'data')
  client.send_queue_message(msg)
  puts 'Sent 1 message'

  receiver = client.create_downstream_receiver

  request = KubeMQ::Queues::QueuePollRequest.new(
    channel: channel,
    max_items: 10,
    wait_timeout: 1
  )
  response = receiver.poll(request)

  if response.error?
    puts "Poll error: #{response.error}"
  else
    puts "Non-blocking poll returned #{response.messages.size} messages:"
    response.messages.each do |m|
      puts "  #{m.metadata}: #{m.body}"
      m.ack
    end
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
