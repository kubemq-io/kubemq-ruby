# frozen_string_literal: true

# Example: Simple Queue Send and Receive (unary API)
# Expected output:
#   Connected to localhost:50000
#   Sent: id=<uuid>, error?=false
#   Received 1 message(s)
#     id=<uuid>, channel=queues.simple.basic, metadata=order-created, body=order-12345
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.simple.basic'

begin
  # Step 2: Create a QueuesClient connected to the broker
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qs-basic-example')
  puts "Connected to #{address}"

  # Step 3: Build and send a queue message with tags
  msg = KubeMQ::Queues::QueueMessage.new(
    channel: channel,
    metadata: 'order-created',
    body: 'order-12345',
    tags: { 'priority' => 'high' }
  )
  result = client.send_queue_message(msg)
  puts "Sent: id=#{result.id}, error?=#{result.error?}"

  # Step 4: Receive messages from the queue (waits up to 5 seconds)
  messages = client.receive_queue_messages(channel: channel, max_messages: 1, wait_timeout_seconds: 5)
  puts "Received #{messages.size} message(s)"
  messages.each do |m|
    puts "  id=#{m.id}, channel=#{m.channel}, metadata=#{m.metadata}, body=#{m.body}"
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 5: Close the client
  client&.close
  puts 'Done'
end
