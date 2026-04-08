# frozen_string_literal: true

# Example: Connect to KubeMQ Broker
# Expected output:
#   Minimal client connected. Server: <version>
#   Configured client connected. Server: <version>
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  # Minimal connection
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'connect-example')
  info = client.ping
  puts "Minimal client connected. Server: #{info.version}"
  client.close

  # Connection with explicit client_id
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'connect-configured')
  info = client.ping
  puts "Configured client connected. Server: #{info.version}"
  client.close
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  puts 'Done'
end
