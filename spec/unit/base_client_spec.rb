# frozen_string_literal: true

RSpec.describe KubeMQ::BaseClient do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(
      KubeMQ::Transport::GrpcTransport,
      kubemq_client: stub_client,
      ensure_connected!: nil,
      close: nil,
      closed?: false
    )
  end
  let(:config) do
    KubeMQ::Configuration.new(address: 'localhost:50000', client_id: 'test-client')
  end

  subject(:client) do
    c = described_class.allocate
    c.instance_variable_set(:@config, config)
    c.instance_variable_set(:@transport, transport)
    c.instance_variable_set(:@closed, false)
    c.instance_variable_set(:@mutex, Mutex.new)
    c
  end

  describe '.new with transport injection' do
    it 'constructs through initialize with provided transport' do
      c = described_class.new(
        address: 'localhost:50000',
        client_id: 'init-test',
        transport: transport
      )
      expect(c.config.address).to eq('localhost:50000')
      expect(c.config.client_id).to eq('init-test')
      expect(c.transport).to eq(transport)
      expect(c).not_to be_closed
    end
  end

  describe '#ping' do
    it 'calls transport.ping' do
      server_info = KubeMQ::ServerInfo.new(
        host: 'h', version: 'v', server_start_time: 0, server_up_time_seconds: 0
      )
      allow(transport).to receive(:ping).and_return(server_info)
      result = client.ping
      expect(result).to eq(server_info)
    end

    it 'raises ClientClosedError when client is closed' do
      client.close
      expect { client.ping }.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe '#close' do
    it 'marks client as closed' do
      client.close
      expect(client).to be_closed
    end

    it 'is idempotent' do
      client.close
      expect { client.close }.not_to raise_error
    end

    it 'delegates to transport.close' do
      expect(transport).to receive(:close)
      client.close
    end
  end

  describe '#closed?' do
    it 'returns false initially' do
      expect(client).not_to be_closed
    end

    it 'returns true after close' do
      client.close
      expect(client).to be_closed
    end
  end

  describe '#create_channel' do
    it 'delegates to ChannelManager' do
      allow(KubeMQ::Transport::ChannelManager).to receive(:create_channel).and_return(true)
      result = client.create_channel(channel_name: 'ch', channel_type: KubeMQ::ChannelType::EVENTS)
      expect(result).to be true
    end

    it 'raises ClientClosedError when closed' do
      client.close
      expect do
        client.create_channel(channel_name: 'ch', channel_type: KubeMQ::ChannelType::EVENTS)
      end.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe '#delete_channel' do
    it 'delegates to ChannelManager' do
      allow(KubeMQ::Transport::ChannelManager).to receive(:delete_channel).and_return(true)
      result = client.delete_channel(channel_name: 'ch', channel_type: KubeMQ::ChannelType::EVENTS)
      expect(result).to be true
    end

    it 'raises ClientClosedError when closed' do
      client.close
      expect do
        client.delete_channel(channel_name: 'ch', channel_type: KubeMQ::ChannelType::EVENTS)
      end.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe '#list_channels' do
    it 'delegates to ChannelManager' do
      allow(KubeMQ::Transport::ChannelManager).to receive(:list_channels).and_return([])
      result = client.list_channels(channel_type: KubeMQ::ChannelType::EVENTS)
      expect(result).to eq([])
    end

    it 'passes search parameter' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::EVENTS, 'test')
        .and_return([])
      client.list_channels(channel_type: KubeMQ::ChannelType::EVENTS, search: 'test')
    end
  end

  describe '#purge_queue_channel' do
    it 'delegates to ChannelManager' do
      allow(KubeMQ::Transport::ChannelManager).to receive(:purge_queue)
        .and_return({ affected_messages: 5 })
      result = client.purge_queue_channel(channel_name: 'q-ch')
      expect(result[:affected_messages]).to eq(5)
    end

    it 'raises ClientClosedError when closed' do
      client.close
      expect do
        client.purge_queue_channel(channel_name: 'q-ch')
      end.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe 'private #ensure_connected!' do
    it 'raises ClientClosedError when closed and calls transport' do
      client.close
      expect { client.send(:ensure_connected!) }.to raise_error(KubeMQ::ClientClosedError)
    end
  end
end
