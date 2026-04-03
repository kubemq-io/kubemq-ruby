# frozen_string_literal: true

# Example: Ping the KubeMQ Broker
# Expected output:
#   Connected to localhost:50000
#   Ping successful:
#     Host:    localhost
#     Version: <server version>
#     Uptime:  <seconds>s
#   Connection closed

require 'kubemq'

# Step 1: Configure the broker address
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  # Step 2: Create a client connected to the broker
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'ping-example')
  puts "Connected to #{address}"

  # Step 3: Ping the broker and display server info
  info = client.ping
  puts 'Ping successful:'
  puts "  Host:    #{info.host}"
  puts "  Version: #{info.version}"
  puts "  Uptime:  #{info.server_up_time_seconds}s"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 4: Close the client connection
  client&.close
  puts 'Connection closed'
end
