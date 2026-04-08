# frozen_string_literal: true

# Example: Reconnection Behavior
# Expected output:
#   Connected to localhost:50000
#   Ping OK: host=localhost, version=<version>
#   Sent heartbeat 0
#   Sent heartbeat 1
#   Sent heartbeat 2
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  client = KubeMQ::PubSubClient.new(
    address: address,
    client_id: 'reconnect-example',
    reconnect_interval: 2
  )
  puts "Connected to #{address}"

  info = client.ping
  puts "Ping OK: host=#{info.host}, version=#{info.version}"

  # Send events periodically to observe reconnection behavior
  channel = 'error_handling.reconnect'
  3.times do |i|
    msg = KubeMQ::PubSub::EventMessage.new(channel: channel, metadata: "heartbeat-#{i}", body: "data-#{i}")
    client.send_event(msg)
    puts "Sent heartbeat #{i}"
    sleep 1
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
