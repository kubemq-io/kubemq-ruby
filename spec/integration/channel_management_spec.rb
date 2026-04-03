# frozen_string_literal: true

RSpec.describe 'Channel Management Integration', :integration do
  def broker_available?
    require 'socket'
    addr = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
    host, port = addr.split(':')
    sock = TCPSocket.new(host, port.to_i)
    sock.close
    true
  rescue StandardError
    false
  end

  before(:all) do
    skip 'requires KubeMQ broker' unless broker_available?
    @pubsub = KubeMQ::PubSubClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-channel-mgmt'
    )
    @queues = KubeMQ::QueuesClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-channel-mgmt-q'
    )
    @cq = KubeMQ::CQClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-channel-mgmt-cq'
    )
  end

  after(:all) do
    @pubsub&.close
    @queues&.close
    @cq&.close
  end

  it 'creates and lists events channel' do
    @pubsub.create_events_channel(channel_name: 'integration.mgmt.events')
    channels = @pubsub.list_events_channels
    names = channels.map(&:name)
    expect(names).to include('integration.mgmt.events')
  end

  it 'creates and lists events_store channel' do
    @pubsub.create_events_store_channel(channel_name: 'integration.mgmt.es')
    channels = @pubsub.list_events_store_channels
    names = channels.map(&:name)
    expect(names).to include('integration.mgmt.es')
  end

  it 'creates and lists queues channel' do
    @queues.create_queues_channel(channel_name: 'integration.mgmt.queues')
    channels = @queues.list_queues_channels
    names = channels.map(&:name)
    expect(names).to include('integration.mgmt.queues')
  end

  it 'creates commands and queries channels' do
    @cq.create_commands_channel(channel_name: 'integration.mgmt.commands')
    @cq.create_queries_channel(channel_name: 'integration.mgmt.queries')

    cmd_channels = @cq.list_commands_channels
    qry_channels = @cq.list_queries_channels
    expect(cmd_channels.map(&:name)).to include('integration.mgmt.commands')
    expect(qry_channels.map(&:name)).to include('integration.mgmt.queries')
  end

  it 'deletes a channel' do
    channel = "integration.mgmt.delete-#{SecureRandom.hex(4)}"
    @pubsub.create_events_channel(channel_name: channel)
    expect { @pubsub.delete_events_channel(channel_name: channel) }.not_to raise_error
  end

  it 'lists channels with search filter' do
    @pubsub.create_events_channel(channel_name: 'integration.mgmt.search-test')
    channels = @pubsub.list_events_channels(search: 'search-test')
    names = channels.map(&:name)
    expect(names).to include('integration.mgmt.search-test')
  end

  it 'purges queue channel' do
    channel = 'integration.mgmt.purge'
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, body: 'purge-me')
    @queues.send_queue_message(msg)
    sleep(0.5)
    result = @queues.purge_queue_channel(channel_name: channel)
    expect(result).to have_key(:affected_messages)
  end

  it 'returns ChannelInfo with correct attributes' do
    @pubsub.create_events_channel(channel_name: 'integration.mgmt.info')
    channels = @pubsub.list_events_channels
    ch = channels.find { |c| c.name == 'integration.mgmt.info' }
    expect(ch).to be_a(KubeMQ::ChannelInfo)
    expect(ch.type).to eq(KubeMQ::ChannelType::EVENTS)
  end
end
