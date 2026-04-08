# frozen_string_literal: true

# Example: Queue Ack/Reject Per Message
# Expected output:
#   Connected to localhost:50000
#   Polled 4 messages
#   Acked: accept-0
#   Rejected: reject-1
#   Acked: accept-2
#   Rejected: reject-3
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.ack_reject'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-ack-reject-example')
  puts "Connected to #{address}"

  # Send messages with alternating accept/reject labels
  4.times do |i|
    label = i.even? ? 'accept' : 'reject'
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "#{label}-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end

  receiver = client.create_downstream_receiver
  request = KubeMQ::Queues::QueuePollRequest.new(channel: channel, max_items: 10, wait_timeout: 5)
  response = receiver.poll(request)

  puts "Polled #{response.messages.size} messages"
  response.messages.each do |m|
    if m.metadata.start_with?('accept')
      m.ack
      puts "Acked: #{m.metadata}"
    else
      m.nack
      puts "Rejected: #{m.metadata}"
    end
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  receiver&.close
  client&.close
  puts 'Done'
end
