# frozen_string_literal: true

# Example: Custom Timeouts and Keep-Alive
# Expected output:
#   Connected with custom timeouts. Server: <version>
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  client = KubeMQ::PubSubClient.new(
    address: address,
    client_id: 'timeout-example',
    default_rpc_timeout: 30,
    keep_alive_ping_time: 10,
    keep_alive_timeout: 5,
    reconnect_interval: 3
  )

  info = client.ping
  puts "Connected with custom timeouts. Server: #{info.version}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
