# frozen_string_literal: true

RSpec.describe 'PubSub Characterization' do
  describe 'EventMessage edge cases' do
    it 'sends event with empty body when metadata present' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'char.events', metadata: 'meta')
      proto = KubeMQ::Transport::Converter.event_to_proto(msg, 'c1')
      expect(proto.Body).to eq(''.b)
    end

    it 'auto-generates unique IDs on each instantiation' do
      ids = 10.times.map { KubeMQ::PubSub::EventMessage.new(channel: 'ch').id }
      expect(ids.uniq.size).to eq(10)
    end

    it 'encodes UTF-8 body to ASCII-8BIT' do
      msg = KubeMQ::PubSub::EventMessage.new(
        channel: 'char.events', body: 'héllo wörld'
      )
      proto = KubeMQ::Transport::Converter.event_to_proto(msg, 'c1')
      expect(proto.Body.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'handles nil tags gracefully' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b')
      msg.tags = nil
      proto = KubeMQ::Transport::Converter.event_to_proto(msg, 'c1')
      expect(proto.Tags.to_h).to eq({})
    end

    it 'preserves empty metadata as empty string' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b', metadata: nil)
      proto = KubeMQ::Transport::Converter.event_to_proto(msg, 'c1')
      expect(proto.Metadata).to eq('')
    end
  end

  describe 'EventsSubscription behavior' do
    it 'group defaults to nil' do
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      expect(sub.group).to be_nil
    end

    it 'channel is mutable' do
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch1')
      sub.channel = 'ch2'
      expect(sub.channel).to eq('ch2')
    end
  end

  describe 'EventsStoreSubscription behavior' do
    it 'StartNewOnly = 1' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_NEW_ONLY).to eq(1)
    end

    it 'StartFromFirst = 2' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST).to eq(2)
    end

    it 'StartFromLast = 3' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_FROM_LAST).to eq(3)
    end

    it 'StartAtSequence = 4' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_AT_SEQUENCE).to eq(4)
    end

    it 'StartAtTime = 5' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_AT_TIME).to eq(5)
    end

    it 'StartAtTimeDelta = 6' do
      expect(KubeMQ::PubSub::EventStoreStartPosition::START_AT_TIME_DELTA).to eq(6)
    end
  end

  describe 'Converter subscribe_to_proto' do
    it 'sets SubscribeTypeData to EVENTS for EventsSubscription' do
      sub = KubeMQ::PubSub::EventsSubscription.new(channel: 'ch')
      proto = KubeMQ::Transport::Converter.subscribe_to_proto(sub, 'c1')
      expect(proto.SubscribeTypeData).to eq(:Events)
    end

    it 'sets SubscribeTypeData to EVENTS_STORE for EventsStoreSubscription' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 1
      )
      proto = KubeMQ::Transport::Converter.subscribe_to_proto(sub, 'c1')
      expect(proto.SubscribeTypeData).to eq(:EventsStore)
    end

    it 'carries start_position_value into proto' do
      sub = KubeMQ::PubSub::EventsStoreSubscription.new(
        channel: 'ch', start_position: 4, start_position_value: 42
      )
      proto = KubeMQ::Transport::Converter.subscribe_to_proto(sub, 'c1')
      expect(proto.EventsStoreTypeValue).to eq(42)
    end
  end
end
