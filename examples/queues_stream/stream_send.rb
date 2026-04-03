# frozen_string_literal: true

# Example: Send Queue Messages via Streaming (upstream sender)
# Expected output:
#   Connected to localhost:50000
#   Created upstream sender
#   Sent: id=<uuid>, error?=false
#   Sent: id=<uuid>, error?=false
#   Sent: id=<uuid>, error?=false
#   Sent: id=<uuid>, error?=false
#   Sent: id=<uuid>, error?=false
#   All messages sent via stream
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queues.stream.send'

begin
  # Step 2: Create a QueuesClient connected to the broker
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'qstream-send-example')
  puts "Connected to #{address}"

  # Step 3: Open a persistent upstream sender stream
  sender = client.create_upstream_sender
  puts 'Created upstream sender'

  # Step 4: Publish 5 messages through the stream
  5.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(
      channel: channel,
      metadata: "stream-item-#{i}",
      body: "payload-#{i}"
    )
    results = sender.publish(msg)
    results.each { |r| puts "Sent: id=#{r.id}, error?=#{r.error?}" }
  end

  puts 'All messages sent via stream'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 5: Close the sender stream and the client
  sender&.close
  client&.close
  puts 'Done'
end
