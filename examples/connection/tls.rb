# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
ca_file = ENV.fetch('KUBEMQ_CA_FILE', '/path/to/ca.pem')

begin
  tls = KubeMQ::TLSConfig.new(enabled: true, ca_file: ca_file)
  client = KubeMQ::PubSubClient.new(
    address: address,
    client_id: 'tls-example',
    tls: tls
  )
  puts "Connected with TLS to #{address}"

  info = client.ping
  puts "Ping OK: host=#{info.host}, version=#{info.version}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Connection closed'
end
