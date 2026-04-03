# frozen_string_literal: true

# Example: Create Channels for All 5 Messaging Patterns
# Expected output:
#   Connected to localhost:50000
#   Created events channel: mgmt.events.test
#   Created events_store channel: mgmt.es.test
#   Created queues channel: mgmt.queues.test
#   Created commands channel: mgmt.commands.test
#   Created queries channel: mgmt.queries.test
#   All 5 channel types created successfully
#   Done

require 'kubemq'

# Step 1: Configure the broker address
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  # Step 2: Create one client per messaging pattern
  pubsub = KubeMQ::PubSubClient.new(address: address, client_id: 'mgmt-create-example')
  queues = KubeMQ::QueuesClient.new(address: address, client_id: 'mgmt-create-example')
  cq = KubeMQ::CQClient.new(address: address, client_id: 'mgmt-create-example')
  puts "Connected to #{address}"

  # Step 3: Create an events channel
  pubsub.create_events_channel(channel_name: 'mgmt.events.test')
  puts 'Created events channel: mgmt.events.test'

  # Step 4: Create an events store channel
  pubsub.create_events_store_channel(channel_name: 'mgmt.es.test')
  puts 'Created events_store channel: mgmt.es.test'

  # Step 5: Create a queues channel
  queues.create_queues_channel(channel_name: 'mgmt.queues.test')
  puts 'Created queues channel: mgmt.queues.test'

  # Step 6: Create a commands channel
  cq.create_commands_channel(channel_name: 'mgmt.commands.test')
  puts 'Created commands channel: mgmt.commands.test'

  # Step 7: Create a queries channel
  cq.create_queries_channel(channel_name: 'mgmt.queries.test')
  puts 'Created queries channel: mgmt.queries.test'

  puts 'All 5 channel types created successfully'
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 8: Close all clients
  pubsub&.close
  queues&.close
  cq&.close
  puts 'Done'
end
