# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  pubsub = KubeMQ::PubSubClient.new(address: address, client_id: 'mgmt-list-example')
  queues = KubeMQ::QueuesClient.new(address: address, client_id: 'mgmt-list-example')
  cq = KubeMQ::CQClient.new(address: address, client_id: 'mgmt-list-example')
  puts "Connected to #{address}"

  puts "\n--- Events Channels ---"
  pubsub.list_events_channels.each { |ch| puts "  #{ch}" }

  puts "\n--- Events Store Channels ---"
  pubsub.list_events_store_channels.each { |ch| puts "  #{ch}" }

  puts "\n--- Queue Channels ---"
  queues.list_queues_channels.each { |ch| puts "  #{ch}" }

  puts "\n--- Command Channels ---"
  cq.list_commands_channels.each { |ch| puts "  #{ch}" }

  puts "\n--- Query Channels ---"
  cq.list_queries_channels.each { |ch| puts "  #{ch}" }

  puts "\n--- Filtered Search (search='mgmt') ---"
  filtered = pubsub.list_events_channels(search: 'mgmt')
  filtered.each { |ch| puts "  #{ch}" }
  puts "Found #{filtered.size} matching channel(s)"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  pubsub&.close
  queues&.close
  cq&.close
  puts 'Done'
end
