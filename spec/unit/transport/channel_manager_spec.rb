# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::ChannelManager do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(KubeMQ::Transport::GrpcTransport, kubemq_client: stub_client)
  end
  let(:client_id) { 'test-client' }

  describe '.create_channel' do
    it 'returns true on success' do
      response = double('Response', Error: '')
      allow(stub_client).to receive(:send_request).and_return(response)
      result = described_class.create_channel(transport, client_id, 'my-ch', KubeMQ::ChannelType::EVENTS)
      expect(result).to be true
    end

    it 'raises ChannelError on error response' do
      response = double('Response', Error: 'channel already exists')
      allow(stub_client).to receive(:send_request).and_return(response)
      expect do
        described_class.create_channel(transport, client_id, 'my-ch', KubeMQ::ChannelType::EVENTS)
      end.to raise_error(KubeMQ::ChannelError, /create_channel failed/)
    end
  end

  describe '.delete_channel' do
    it 'returns true on success' do
      response = double('Response', Error: '')
      allow(stub_client).to receive(:send_request).and_return(response)
      result = described_class.delete_channel(transport, client_id, 'my-ch', KubeMQ::ChannelType::EVENTS)
      expect(result).to be true
    end

    it 'raises ChannelError on error response' do
      response = double('Response', Error: 'not found')
      allow(stub_client).to receive(:send_request).and_return(response)
      expect do
        described_class.delete_channel(transport, client_id, 'del-ch', KubeMQ::ChannelType::EVENTS)
      end.to raise_error(KubeMQ::ChannelError, /delete_channel failed/)
    end
  end

  describe '.list_channels' do
    it 'returns channel list on success' do
      body = +'[{"name":"ch1","lastActivity":100,"isActive":true,"incoming":5,"outgoing":3}]'
      response = double('Response', Error: '', Body: body)
      allow(stub_client).to receive(:send_request).and_return(response)

      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels.size).to eq(1)
      expect(channels.first).to be_a(KubeMQ::ChannelInfo)
      expect(channels.first.name).to eq('ch1')
      expect(channels.first).to be_active
    end

    it 'returns empty array for nil body' do
      response = double('Response', Error: '', Body: nil)
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels).to eq([])
    end

    it 'returns empty array for empty body' do
      response = double('Response', Error: '', Body: '')
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels).to eq([])
    end

    it 'returns empty array for malformed JSON' do
      response = double('Response', Error: '', Body: +'not-json')
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels).to eq([])
    end

    it 'includes search tag when search is provided' do
      response = double('Response', Error: '', Body: +'[]')
      expect(stub_client).to receive(:send_request) do |req|
        expect(req.Tags['channel_search']).to eq('test')
        response
      end
      described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS, 'test')
    end

    it 'omits search tag when search is nil' do
      response = double('Response', Error: '', Body: +'[]')
      expect(stub_client).to receive(:send_request) do |req|
        expect(req.Tags).not_to have_key('channel_search')
        response
      end
      described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS, nil)
    end

    it 'omits search tag when search is empty string' do
      response = double('Response', Error: '', Body: +'[]')
      expect(stub_client).to receive(:send_request) do |req|
        expect(req.Tags).not_to have_key('channel_search')
        response
      end
      described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS, '')
    end

    it 'handles channels key in response body' do
      body = +'{"channels":[{"name":"c1"},{"name":"c2"}]}'
      response = double('Response', Error: '', Body: body)
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels.size).to eq(2)
    end

    it 'handles items key in response body' do
      body = +'{"items":[{"name":"c1"}]}'
      response = double('Response', Error: '', Body: body)
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels.size).to eq(1)
    end

    it 'wraps single-object response in array' do
      body = +'{"name":"single-ch"}'
      response = double('Response', Error: '', Body: body)
      allow(stub_client).to receive(:send_request).and_return(response)
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels.size).to eq(1)
      expect(channels.first.name).to eq('single-ch')
    end

    it 'retries on "cluster snapshot not ready" error' do
      attempt = 0
      response = double('Response', Error: '', Body: +'[]')
      allow(stub_client).to receive(:send_request) do
        attempt += 1
        raise 'cluster snapshot not ready' if attempt == 1

        response
      end
      channels = described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      expect(channels).to eq([])
      expect(attempt).to eq(2)
    end

    it 'raises ChannelError after exhausting retries' do
      allow(stub_client).to receive(:send_request)
        .and_raise('cluster snapshot not ready')
      expect do
        described_class.list_channels(transport, client_id, KubeMQ::ChannelType::EVENTS)
      end.to raise_error(KubeMQ::ChannelError, /list_channels failed after/)
    end
  end

  describe '.purge_queue' do
    it 'returns affected_messages on success' do
      response = double('Response', IsError: false, Error: '', AffectedMessages: 10)
      allow(stub_client).to receive(:ack_all_queue_messages).and_return(response)
      result = described_class.purge_queue(transport, client_id, 'q-ch')
      expect(result).to eq({ affected_messages: 10 })
    end

    it 'raises ChannelError on error response' do
      response = double('Response', IsError: true, Error: 'queue not found')
      allow(stub_client).to receive(:ack_all_queue_messages).and_return(response)
      expect do
        described_class.purge_queue(transport, client_id, 'q-ch')
      end.to raise_error(KubeMQ::ChannelError, /Failed to purge queue/)
    end
  end

  describe '.build_request' do
    it 'builds a valid proto request' do
      request = described_class.build_request(
        client_id: client_id,
        metadata: 'test-op',
        tags: { 'key' => 'val' }
      )
      expect(request).to be_a(Kubemq::Request)
      expect(request.ClientID).to eq(client_id)
      expect(request.Metadata).to eq('test-op')
      expect(request.Channel).to eq(KubeMQ::Transport::ChannelManager::INTERNAL_CHANNEL)
      expect(request.Tags['key']).to eq('val')
    end
  end

  describe '.check_response_error!' do
    it 'returns nil when no error' do
      response = double('Response', Error: nil)
      expect(described_class.check_response_error!(response, 'test')).to be_nil
    end

    it 'returns nil when error is empty' do
      response = double('Response', Error: '')
      expect(described_class.check_response_error!(response, 'test')).to be_nil
    end

    it 'raises ChannelError when error is present' do
      response = double('Response', Error: 'something went wrong')
      expect do
        described_class.check_response_error!(response, 'test_op', 'ch-1')
      end.to raise_error(KubeMQ::ChannelError) { |err|
        expect(err.operation).to eq('test_op')
        expect(err.channel).to eq('ch-1')
      }
    end
  end
end
