# frozen_string_literal: true

# Example: Connection Error Handling
# Expected output:
#   Attempting connection to bad address...
#   Connection error (expected): <error message>
#   Done

require 'kubemq'

begin
  # Attempt to connect to a non-existent server
  puts 'Attempting connection to bad address...'
  client = KubeMQ::PubSubClient.new(address: 'localhost:59999', client_id: 'error-example')
  client.ping
  puts 'Connected (unexpected)'
rescue KubeMQ::Error => e
  puts "Connection error (expected): #{e.message}"
rescue StandardError => e
  puts "Connection error (expected): #{e.message}"
ensure
  client&.close
  puts 'Done'
end
