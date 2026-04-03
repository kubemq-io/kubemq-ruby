# frozen_string_literal: true

RSpec.describe KubeMQ::PubSub::EventMessage do
  describe '#initialize' do
    it 'requires channel keyword' do
      msg = described_class.new(channel: 'test-ch', body: 'hello')
      expect(msg.channel).to eq('test-ch')
      expect(msg.body).to eq('hello')
    end

    it 'auto-generates UUID for id when nil' do
      msg = described_class.new(channel: 'ch')
      expect(msg.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'uses provided id' do
      msg = described_class.new(channel: 'ch', id: 'custom-id')
      expect(msg.id).to eq('custom-id')
    end

    it 'defaults tags to empty hash' do
      msg = described_class.new(channel: 'ch')
      expect(msg.tags).to eq({})
    end

    it 'accepts metadata, body, and tags' do
      msg = described_class.new(
        channel: 'ch', metadata: 'meta',
        body: 'body', tags: { 'k' => 'v' }
      )
      expect(msg.metadata).to eq('meta')
      expect(msg.body).to eq('body')
      expect(msg.tags).to eq({ 'k' => 'v' })
    end

    it 'defaults metadata and body to nil' do
      msg = described_class.new(channel: 'ch')
      expect(msg.metadata).to be_nil
      expect(msg.body).to be_nil
    end
  end
end

RSpec.describe KubeMQ::PubSub::EventStoreMessage do
  describe '#initialize' do
    it 'auto-generates UUID for id' do
      msg = described_class.new(channel: 'es-ch')
      expect(msg.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'accepts all fields' do
      msg = described_class.new(
        channel: 'es-ch', metadata: 'm',
        body: 'b', tags: { 'a' => '1' }, id: 'es-1'
      )
      expect(msg.id).to eq('es-1')
      expect(msg.channel).to eq('es-ch')
    end
  end
end

RSpec.describe KubeMQ::PubSub::EventSendResult do
  it 'stores id, sent, and error' do
    result = described_class.new(id: 'r1', sent: true, error: nil)
    expect(result.id).to eq('r1')
    expect(result.sent).to be true
    expect(result.error).to be_nil
  end

  it 'stores error message' do
    result = described_class.new(id: 'r2', sent: false, error: 'failed')
    expect(result.error).to eq('failed')
  end
end

RSpec.describe KubeMQ::PubSub::EventReceived do
  it 'stores all fields' do
    received = described_class.new(
      id: 'ev-1', channel: 'ch', metadata: 'meta',
      body: 'body', timestamp: 123, sequence: 1, tags: { 'k' => 'v' }
    )
    expect(received.id).to eq('ev-1')
    expect(received.channel).to eq('ch')
    expect(received.timestamp).to eq(123)
    expect(received.sequence).to eq(1)
    expect(received.tags).to eq({ 'k' => 'v' })
  end
end

RSpec.describe KubeMQ::PubSub::EventStoreReceived do
  it 'includes sequence number' do
    received = described_class.new(
      id: 'es-1', channel: 'ch', metadata: 'm',
      body: 'b', timestamp: 456, sequence: 42, tags: {}
    )
    expect(received.sequence).to eq(42)
  end

  it 'includes timestamp' do
    received = described_class.new(
      id: 'es-2', channel: 'ch', metadata: '',
      body: 'b', timestamp: 789, sequence: 1, tags: {}
    )
    expect(received.timestamp).to eq(789)
  end
end

RSpec.describe KubeMQ::PubSub::EventsSubscription do
  it 'stores channel and group' do
    sub = described_class.new(channel: 'events.test', group: 'g1')
    expect(sub.channel).to eq('events.test')
    expect(sub.group).to eq('g1')
  end

  it 'defaults group to nil' do
    sub = described_class.new(channel: 'events.test')
    expect(sub.group).to be_nil
  end
end

RSpec.describe KubeMQ::PubSub::EventsStoreSubscription do
  it 'stores channel, start_position, and start_position_value' do
    sub = described_class.new(
      channel: 'es.test',
      start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST,
      start_position_value: 0
    )
    expect(sub.channel).to eq('es.test')
    expect(sub.start_position).to eq(2)
    expect(sub.start_position_value).to eq(0)
  end

  it 'stores group' do
    sub = described_class.new(
      channel: 'es.test',
      start_position: 1,
      group: 'grp'
    )
    expect(sub.group).to eq('grp')
  end
end

RSpec.describe KubeMQ::PubSub::EventStoreResult do
  it 'stores id, sent, and error' do
    result = described_class.new(id: 'esr-1', sent: true)
    expect(result.id).to eq('esr-1')
    expect(result.sent).to be true
    expect(result.error).to be_nil
  end
end
