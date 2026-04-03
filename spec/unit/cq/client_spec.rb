# frozen_string_literal: true

RSpec.describe KubeMQ::CQClient do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(
      KubeMQ::Transport::GrpcTransport,
      kubemq_client: stub_client,
      ensure_connected!: nil,
      register_subscription: nil,
      unregister_subscription: nil,
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

  describe '#send_command' do
    let(:proto_response) do
      double('Response',
             ClientID: 'c1', RequestID: 'r1', Executed: true,
             Timestamp: 100, Error: '', Tags: {})
    end

    before { allow(stub_client).to receive(:send_request).and_return(proto_response) }

    it 'returns CommandResponse' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'cmd.ch', timeout: 5000, body: 'data'
      )
      result = client.send_command(msg)
      expect(result).to be_a(KubeMQ::CQ::CommandResponse)
      expect(result.executed).to be true
    end

    it 'validates channel' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: '', timeout: 5000, body: 'data')
      expect { client.send_command(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates content' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: 'ch', timeout: 5000)
      expect { client.send_command(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates timeout is positive' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: 'ch', timeout: 0, body: 'b')
      expect { client.send_command(msg) }
        .to raise_error(KubeMQ::ValidationError, /Timeout must be greater than 0/)
    end

    it 'validates timeout is not negative' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: 'ch', timeout: -1, body: 'b')
      expect { client.send_command(msg) }
        .to raise_error(KubeMQ::ValidationError, /Timeout must be greater than 0/)
    end
  end

  describe '#subscribe_to_commands' do
    it 'requires a block' do
      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'cmd.ch')
      expect { client.subscribe_to_commands(sub) }
        .to raise_error(ArgumentError, /Block required/)
    end

    it 'validates channel (no wildcards)' do
      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'cmd.*')
      expect do
        client.subscribe_to_commands(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'returns a Thread for valid subscription' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_requests).and_return(stream)
      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'cmd.ch')
      thread = client.subscribe_to_commands(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end
  end

  describe '#send_response' do
    before { allow(stub_client).to receive(:send_response).and_return(nil) }

    it 'validates request_id' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: '', reply_channel: 'reply', executed: true
      )
      expect { client.send_response(resp) }
        .to raise_error(KubeMQ::ValidationError, /request_id is required/)
    end

    it 'validates reply_channel' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: '', executed: true
      )
      expect { client.send_response(resp) }
        .to raise_error(KubeMQ::ValidationError, /reply_channel is required/)
    end

    it 'sends valid response' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: 'reply-ch', executed: true
      )
      expect(client.send_response(resp)).to be_nil
    end
  end

  describe '#send_query' do
    let(:proto_response) do
      double('Response',
             ClientID: 'c1', RequestID: 'r1', Executed: true,
             Metadata: 'm', Body: 'result', CacheHit: false,
             Timestamp: 100, Error: '', Tags: {})
    end

    before { allow(stub_client).to receive(:send_request).and_return(proto_response) }

    it 'returns QueryResponse' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'q.ch', timeout: 5000, body: 'query'
      )
      result = client.send_query(msg)
      expect(result).to be_a(KubeMQ::CQ::QueryResponse)
      expect(result.executed).to be true
      expect(result.body).to eq('result')
    end

    it 'validates cache_ttl when cache_key is set' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'q.ch', timeout: 5000, body: 'q',
        cache_key: 'ck', cache_ttl: 0
      )
      expect { client.send_query(msg) }
        .to raise_error(KubeMQ::ValidationError, /cache_ttl must be > 0/)
    end

    it 'validates timeout' do
      msg = KubeMQ::CQ::QueryMessage.new(channel: 'ch', timeout: 0, body: 'b')
      expect { client.send_query(msg) }
        .to raise_error(KubeMQ::ValidationError, /Timeout must be greater than 0/)
    end
  end

  describe '#subscribe_to_queries' do
    it 'requires a block' do
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'q.ch')
      expect { client.subscribe_to_queries(sub) }
        .to raise_error(ArgumentError, /Block required/)
    end

    it 'validates channel (no wildcards)' do
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'q.*')
      expect do
        client.subscribe_to_queries(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'returns a Thread for valid subscription' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_requests).and_return(stream)
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'q.ch')
      thread = client.subscribe_to_queries(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end
  end

  describe '#send_query with cache' do
    let(:proto_response) do
      double('Response',
             ClientID: 'c1', RequestID: 'r1', Executed: true,
             Metadata: 'm', Body: 'cached', CacheHit: true,
             Timestamp: 100, Error: '', Tags: {})
    end

    before { allow(stub_client).to receive(:send_request).and_return(proto_response) }

    it 'allows valid cache_key and cache_ttl' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'q.ch', timeout: 5000, body: 'q',
        cache_key: 'ck', cache_ttl: 60
      )
      result = client.send_query(msg)
      expect(result).to be_a(KubeMQ::CQ::QueryResponse)
      expect(result.cache_hit).to be true
    end
  end

  describe '#subscribe_to_commands error handling' do
    it 'calls on_error for GRPC::BadStatus' do
      error_received = nil
      grpc_err = GRPC::BadStatus.new(14, 'unavailable')
      allow(stub_client).to receive(:subscribe_to_requests).and_raise(grpc_err)

      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'cmd.ch')
      thread = client.subscribe_to_commands(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end

    it 'calls on_error for StandardError' do
      error_received = nil
      allow(stub_client).to receive(:subscribe_to_requests).and_raise(RuntimeError, 'unexpected')

      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'cmd.ch')
      thread = client.subscribe_to_commands(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end
  end

  describe '#subscribe_to_queries error handling' do
    it 'calls on_error for GRPC::BadStatus' do
      error_received = nil
      grpc_err = GRPC::BadStatus.new(14, 'unavailable')
      allow(stub_client).to receive(:subscribe_to_requests).and_raise(grpc_err)

      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'q.ch')
      thread = client.subscribe_to_queries(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end

    it 'calls on_error for StandardError' do
      error_received = nil
      allow(stub_client).to receive(:subscribe_to_requests).and_raise(RuntimeError, 'err')

      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'q.ch')
      thread = client.subscribe_to_queries(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end
  end

  describe 'channel management' do
    before do
      allow(KubeMQ::Transport::ChannelManager).to receive(:create_channel).and_return(true)
      allow(KubeMQ::Transport::ChannelManager).to receive(:delete_channel).and_return(true)
      allow(KubeMQ::Transport::ChannelManager).to receive(:list_channels).and_return([])
    end

    it '#create_commands_channel uses COMMANDS type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:create_channel)
        .with(transport, 'test-client', 'cmd-ch', KubeMQ::ChannelType::COMMANDS)
      client.create_commands_channel(channel_name: 'cmd-ch')
    end

    it '#create_queries_channel uses QUERIES type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:create_channel)
        .with(transport, 'test-client', 'q-ch', KubeMQ::ChannelType::QUERIES)
      client.create_queries_channel(channel_name: 'q-ch')
    end

    it '#delete_commands_channel uses COMMANDS type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:delete_channel)
        .with(transport, 'test-client', 'cmd-ch', KubeMQ::ChannelType::COMMANDS)
      client.delete_commands_channel(channel_name: 'cmd-ch')
    end

    it '#delete_queries_channel uses QUERIES type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:delete_channel)
        .with(transport, 'test-client', 'q-ch', KubeMQ::ChannelType::QUERIES)
      client.delete_queries_channel(channel_name: 'q-ch')
    end

    it '#list_commands_channels delegates correctly' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::COMMANDS, nil)
      client.list_commands_channels
    end

    it '#list_commands_channels passes search' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::COMMANDS, 'test')
      client.list_commands_channels(search: 'test')
    end

    it '#list_queries_channels delegates correctly' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::QUERIES, nil)
      client.list_queries_channels
    end

    it '#list_queries_channels passes search' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::QUERIES, 'test')
      client.list_queries_channels(search: 'test')
    end
  end
end
