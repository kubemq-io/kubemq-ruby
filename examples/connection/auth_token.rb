# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
token = ENV.fetch('KUBEMQ_AUTH_TOKEN', 'your-auth-token-here')

begin
  client = KubeMQ::PubSubClient.new(
    address: address,
    client_id: 'auth-token-example',
    auth_token: token
  )
  puts "Connected with auth token to #{address}"

  info = client.ping
  puts "Ping OK: host=#{info.host}, version=#{info.version}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Connection closed'
end
