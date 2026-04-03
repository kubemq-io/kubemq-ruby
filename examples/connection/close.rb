# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  client = KubeMQ::PubSubClient.new(address: address, client_id: 'close-example')
  puts "Connected to #{address}"

  info = client.ping
  puts "Ping OK: host=#{info.host}, version=#{info.version}"

  client.close
  puts "Client closed (closed?=#{client.closed?})"

  client.close
  puts 'Second close is safe (idempotent)'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
end
