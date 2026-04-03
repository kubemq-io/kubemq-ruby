# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
cert_file = ENV.fetch('KUBEMQ_CERT_FILE', '/path/to/client.pem')
key_file = ENV.fetch('KUBEMQ_KEY_FILE', '/path/to/client-key.pem')
ca_file = ENV.fetch('KUBEMQ_CA_FILE', '/path/to/ca.pem')

begin
  tls = KubeMQ::TLSConfig.new(
    enabled: true,
    cert_file: cert_file,
    key_file: key_file,
    ca_file: ca_file
  )
  client = KubeMQ::PubSubClient.new(
    address: address,
    client_id: 'mtls-example',
    tls: tls
  )
  puts "Connected with mTLS to #{address}"

  info = client.ping
  puts "Ping OK: host=#{info.host}, version=#{info.version}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Connection closed'
end
