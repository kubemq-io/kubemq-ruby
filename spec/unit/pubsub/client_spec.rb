# frozen_string_literal: true

RSpec.describe KubeMQ::PubSubClient do
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
    c.instance_variable_set(:@senders, [])
    c.instance_variable_set(:@senders_mutex, Mutex.new)
    c
  end

  describe '#send_event' do
    let(:proto_result) do
      double('Result', EventID: 'ev-1', Sent: true, Error: '')
    end

    before { allow(stub_client).to receive(:send_event).and_return(proto_result) }

    it 'returns EventSendResult' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'data')
      result = client.send_event(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventSendResult)
      expect(result.id).to eq('ev-1')
      expect(result.sent).to be true
    end

    it 'validates channel' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: '', body: 'data')
      expect { client.send_event(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates content' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch')
      expect { client.send_event(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'accepts metadata only' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', metadata: 'meta')
      result = client.send_event(msg)
      expect(result.sent).to be true
    end

    it 'accepts body only' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'body')
      result = client.send_event(msg)
      expect(result.sent).to be true
    end
  end

  describe '#send_event_store' do
    let(:proto_result) do
      double('Result', EventID: 'es-1', Sent: true, Error: '')
    end

    before { allow(stub_client).to receive(:send_event).and_return(proto_result) }

    it 'returns EventStoreResult' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'es.ch', body: 'data')
      result = client.send_event_store(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventStoreResult)
      expect(result.sent).to be true
    end
  end

  describe '#subscribe_to_events' do
    it 'requires a block' do
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      expect { client.subscribe_to_events(sub) }.to raise_error(ArgumentError, /Block required/)
    end

    it 'validates channel allowing wildcards' do
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: '')
      expect do
        client.subscribe_to_events(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError)
    end

    it 'returns a Thread' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      thread = client.subscribe_to_events(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end

    it 'allows wildcard * in events subscription' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'test.*')
      thread = client.subscribe_to_events(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end

    it 'allows wildcard > in events subscription' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'test.>')
      thread = client.subscribe_to_events(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end
  end

  describe '#subscribe_to_events_store' do
    it 'requires a block' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 1
      )
      expect { client.subscribe_to_events_store(sub) }
        .to raise_error(ArgumentError, /Block required/)
    end

    it 'rejects wildcard in events store subscription' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'test.*', start_position: 1
      )
      expect do
        client.subscribe_to_events_store(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'validates start_position is not 0' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 0
      )
      expect do
        client.subscribe_to_events_store(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /requires a start position/)
    end

    it 'validates StartAtSequence requires positive value' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 4, start_position_value: 0
      )
      expect do
        client.subscribe_to_events_store(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /StartAtSequence requires a positive/)
    end

    it 'returns a Thread for valid subscription' do
      stream = [].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 1
      )
      thread = client.subscribe_to_events_store(sub) { |_| nil }
      expect(thread).to be_a(KubeMQ::Subscription)
      thread.cancel
    end
  end

  describe '#create_events_sender' do
    it 'returns an EventSender' do
      allow(stub_client).to receive(:send_events_stream) { [].each }
      sender = client.create_events_sender
      expect(sender).to be_a(KubeMQ::PubSub::EventSender)
      sender.close
    end
  end

  describe '#create_events_store_sender' do
    it 'returns an EventStoreSender' do
      allow(stub_client).to receive(:send_events_stream) { [].each }
      sender = client.create_events_store_sender
      expect(sender).to be_a(KubeMQ::PubSub::EventStoreSender)
      sender.close
    end
  end

  describe '#send_event_store with error result' do
    let(:proto_result) do
      double('Result', EventID: 'es-err', Sent: false, Error: 'store error')
    end

    before { allow(stub_client).to receive(:send_event).and_return(proto_result) }

    it 'returns EventStoreResult with error' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'es.ch', body: 'data')
      result = client.send_event_store(msg)
      expect(result.error).to eq('store error')
      expect(result.sent).to be false
    end
  end

  describe '#subscribe_to_events with cancellation_token' do
    it 'breaks when cancellation_token is cancelled' do
      event = double('EventReceive',
                     EventID: 'ev-1', Channel: 'ch',
                     Metadata: 'meta', Body: 'body', Tags: {})
      stream = [event].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      allow(KubeMQ::Transport::Converter).to receive(:proto_to_event_received)
        .and_return({ id: 'ev-1', channel: 'ch', metadata: 'meta', body: 'body', tags: {} })

      token = KubeMQ::CancellationToken.new
      token.cancel
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      received = []
      thread = client.subscribe_to_events(sub, cancellation_token: token) { |ev| received << ev }
      thread.cancel
      expect(received).to be_empty
    end
  end

  describe '#subscribe_to_events_store with cancellation_token' do
    it 'breaks when cancellation_token is cancelled' do
      event = double('EventReceive',
                     EventID: 'es-1', Channel: 'ch',
                     Metadata: 'meta', Body: 'body', Tags: {})
      stream = [event].each
      allow(stub_client).to receive(:subscribe_to_events).and_return(stream)
      allow(KubeMQ::Transport::Converter).to receive(:proto_to_event_received)
        .and_return({ id: 'es-1', channel: 'ch', metadata: 'meta', body: 'body', tags: {} })

      token = KubeMQ::CancellationToken.new
      token.cancel
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(channel: 'ch', start_position: 1)
      received = []
      thread = client.subscribe_to_events_store(sub, cancellation_token: token) { |ev| received << ev }
      thread.cancel
      expect(received).to be_empty
    end
  end

  describe '#subscribe_to_events error handling' do
    it 'calls on_error for GRPC::BadStatus' do
      error_received = nil
      grpc_err = GRPC::BadStatus.new(14, 'unavailable')
      allow(stub_client).to receive(:subscribe_to_events).and_raise(grpc_err)

      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      thread = client.subscribe_to_events(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end

    it 'calls on_error for StandardError' do
      error_received = nil
      allow(stub_client).to receive(:subscribe_to_events).and_raise(RuntimeError, 'unexpected')

      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      thread = client.subscribe_to_events(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      expect(error_received.message).to include('unexpected')
      thread.cancel
    end
  end

  describe '#subscribe_to_events_store error handling' do
    it 'calls on_error for GRPC::BadStatus' do
      error_received = nil
      grpc_err = GRPC::BadStatus.new(14, 'unavailable')
      allow(stub_client).to receive(:subscribe_to_events).and_raise(grpc_err)

      sub = KubeMQ::PubSub::EventsStoreSubscription.new(channel: 'ch', start_position: 1)
      thread = client.subscribe_to_events_store(
        sub,
        on_error: ->(e) { error_received = e }
      ) { |_| nil }
      thread.join(2)
      expect(error_received).to be_a(KubeMQ::Error)
      thread.cancel
    end

    it 'calls on_error for StandardError' do
      error_received = nil
      allow(stub_client).to receive(:subscribe_to_events).and_raise(RuntimeError, 'runtime err')

      sub = KubeMQ::PubSub::EventsStoreSubscription.new(channel: 'ch', start_position: 1)
      thread = client.subscribe_to_events_store(
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

    it '#create_events_channel delegates to ChannelManager' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:create_channel)
        .with(transport, 'test-client', 'new-ch', KubeMQ::ChannelType::EVENTS)
      client.create_events_channel(channel_name: 'new-ch')
    end

    it '#delete_events_channel delegates to ChannelManager' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:delete_channel)
        .with(transport, 'test-client', 'del-ch', KubeMQ::ChannelType::EVENTS)
      client.delete_events_channel(channel_name: 'del-ch')
    end

    it '#list_events_channels delegates to ChannelManager' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::EVENTS, nil)
      client.list_events_channels
    end

    it '#list_events_channels passes search' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::EVENTS, 'test')
      client.list_events_channels(search: 'test')
    end

    it '#create_events_store_channel delegates with correct type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:create_channel)
        .with(transport, 'test-client', 'es-ch', KubeMQ::ChannelType::EVENTS_STORE)
      client.create_events_store_channel(channel_name: 'es-ch')
    end

    it '#delete_events_store_channel delegates with correct type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:delete_channel)
        .with(transport, 'test-client', 'es-ch', KubeMQ::ChannelType::EVENTS_STORE)
      client.delete_events_store_channel(channel_name: 'es-ch')
    end

    it '#list_events_store_channels delegates with correct type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::EVENTS_STORE, nil)
      client.list_events_store_channels
    end

    it '#list_events_store_channels passes search' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::EVENTS_STORE, 'search')
      client.list_events_store_channels(search: 'search')
    end
  end
end
