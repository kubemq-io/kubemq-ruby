# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')

begin
  pubsub = KubeMQ::PubSubClient.new(address: address, client_id: 'mgmt-delete-example')
  puts "Connected to #{address}"

  pubsub.create_events_channel(channel_name: 'mgmt.delete.test')
  puts 'Created channel: mgmt.delete.test'

  channels = pubsub.list_events_channels(search: 'mgmt.delete')
  puts "Before delete: #{channels.size} channel(s) found"

  pubsub.delete_events_channel(channel_name: 'mgmt.delete.test')
  puts 'Deleted channel: mgmt.delete.test'

  channels = pubsub.list_events_channels(search: 'mgmt.delete')
  puts "After delete: #{channels.size} channel(s) found"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  pubsub&.close
  puts 'Done'
end
