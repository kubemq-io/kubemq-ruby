# frozen_string_literal: true

RSpec.describe 'PubSub Integration', :integration do
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
    @client = KubeMQ::PubSubClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-integration-pubsub'
    )
  end

  after(:all) do
    @client&.close
  end

  describe 'Events' do
    it 'sends event via unary RPC and receives EventSendResult' do
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'integration.events.test', body: 'hello'
      )
      result = @client.send_event(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventSendResult)
    end

    it 'sends event with metadata only' do
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'integration.events.meta', metadata: 'meta-only'
      )
      result = @client.send_event(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventSendResult)
    end

    it 'sends event with tags' do
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'integration.events.tags', body: 'tagged',
        tags: { 'env' => 'test' }
      )
      result = @client.send_event(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventSendResult)
    end

    it 'subscribes to events channel and receives EventReceived' do
      received_events = []
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'integration.events.sub')

      thread = @client.subscribe_to_events(sub, cancellation_token: token) do |event|
        received_events << event
      end

      sleep(0.5)
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'integration.events.sub', body: 'sub-test'
      )
      @client.send_event(msg)
      sleep(1)
      token.cancel
      thread.join(3)

      expect(received_events).not_to be_empty
      expect(received_events.first).to be_a(KubeMQ::PubSub::EventReceived)
    end

    it 'cancels subscription via CancellationToken' do
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'integration.events.cancel')
      subscription = @client.subscribe_to_events(sub, cancellation_token: token) { |_| nil }
      sleep(0.3)
      subscription.cancel
      subscription.join(3)
      expect(subscription).not_to be_active
    end

    it 'sends event via stream sender' do
      sender = @client.create_events_sender
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'integration.events.stream', body: 'stream-data'
      )
      expect { sender.publish(msg) }.not_to raise_error
      sender.close
    end
  end

  describe 'Events Store' do
    it 'sends event store message and receives result' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(
        channel: 'integration.es.test', body: 'store-hello'
      )
      result = @client.send_event_store(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventStoreResult)
      expect(result.sent).to be true
    end

    it 'subscribes with StartNewOnly' do
      received = []
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'integration.es.startnew',
        start_position: KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY
      )

      thread = @client.subscribe_to_events_store(sub, cancellation_token: token) do |ev|
        received << ev
      end

      sleep(0.5)
      msg = KubeMQ::PubSub::EventStoreMessage.new(
        channel: 'integration.es.startnew', body: 'new-msg'
      )
      @client.send_event_store(msg)
      sleep(1)
      token.cancel
      thread.join(3)

      expect(received).not_to be_empty
    end

    it 'sends event store via stream sender with confirmation' do
      sender = @client.create_events_store_sender
      msg = KubeMQ::PubSub::EventStoreMessage.new(
        channel: 'integration.es.stream', body: 'stream-store'
      )
      result = sender.publish(msg)
      expect(result).to be_a(KubeMQ::PubSub::EventStoreResult)
      expect(result.sent).to be true
      sender.close
    end

    it 'raises ValidationError for wildcard in Events Store subscribe' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'integration.es.*',
        start_position: 1
      )
      expect do
        @client.subscribe_to_events_store(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'rejects Undefined start_position' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'integration.es.undefined',
        start_position: 0
      )
      expect do
        @client.subscribe_to_events_store(sub) { |_| nil }
      end.to raise_error(KubeMQ::ValidationError, /requires a start position/)
    end

    it 'subscribes with consumer group' do
      received = []
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'integration.es.group',
        start_position: 1,
        group: 'test-group'
      )

      thread = @client.subscribe_to_events_store(sub, cancellation_token: token) do |ev|
        received << ev
      end

      sleep(0.5)
      token.cancel
      thread.join(3)
    end
  end
end
