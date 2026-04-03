# frozen_string_literal: true

RSpec.describe KubeMQ::CQ::CommandMessage do
  describe '#initialize' do
    it 'auto-generates UUID for id when nil' do
      msg = described_class.new(channel: 'cmd.ch', timeout: 5000)
      expect(msg.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'uses provided id' do
      msg = described_class.new(channel: 'cmd.ch', timeout: 5000, id: 'cmd-1')
      expect(msg.id).to eq('cmd-1')
    end

    it 'stores channel and timeout' do
      msg = described_class.new(channel: 'cmd.ch', timeout: 5000)
      expect(msg.channel).to eq('cmd.ch')
      expect(msg.timeout).to eq(5000)
    end

    it 'defaults tags to empty hash' do
      msg = described_class.new(channel: 'ch', timeout: 1000)
      expect(msg.tags).to eq({})
    end
  end
end

RSpec.describe KubeMQ::CQ::CommandResponse do
  it 'stores all fields' do
    resp = described_class.new(
      client_id: 'c1', request_id: 'r1',
      executed: true, timestamp: 100, tags: { 'a' => 'b' }
    )
    expect(resp.client_id).to eq('c1')
    expect(resp.request_id).to eq('r1')
    expect(resp.executed).to be true
    expect(resp.tags).to eq({ 'a' => 'b' })
  end

  it 'defaults error to nil' do
    resp = described_class.new(client_id: 'c1', request_id: 'r1', executed: true)
    expect(resp.error).to be_nil
  end
end

RSpec.describe KubeMQ::CQ::CommandResponseMessage do
  it 'stores request_id and reply_channel' do
    msg = described_class.new(
      request_id: 'r1', reply_channel: 'reply-ch', executed: true
    )
    expect(msg.request_id).to eq('r1')
    expect(msg.reply_channel).to eq('reply-ch')
    expect(msg.executed).to be true
  end

  it 'stores error and tags' do
    msg = described_class.new(
      request_id: 'r1', reply_channel: 'ch',
      executed: false, error: 'fail', tags: { 'k' => 'v' }
    )
    expect(msg.error).to eq('fail')
    expect(msg.tags).to eq({ 'k' => 'v' })
  end
end

RSpec.describe KubeMQ::CQ::CommandReceived do
  it 'stores all fields including reply_channel' do
    received = described_class.new(
      id: 'cr-1', channel: 'cmd.ch',
      metadata: 'm', body: 'b',
      reply_channel: 'reply-ch', tags: { 't' => '1' }
    )
    expect(received.id).to eq('cr-1')
    expect(received.reply_channel).to eq('reply-ch')
    expect(received.tags).to eq({ 't' => '1' })
  end
end

RSpec.describe KubeMQ::CQ::QueryMessage do
  describe '#initialize' do
    it 'auto-generates UUID for id' do
      msg = described_class.new(channel: 'q.ch', timeout: 5000)
      expect(msg.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'stores cache_key and cache_ttl' do
      msg = described_class.new(
        channel: 'q.ch', timeout: 5000,
        cache_key: 'ck', cache_ttl: 60
      )
      expect(msg.cache_key).to eq('ck')
      expect(msg.cache_ttl).to eq(60)
    end

    it 'defaults cache fields to nil' do
      msg = described_class.new(channel: 'q.ch', timeout: 5000)
      expect(msg.cache_key).to be_nil
      expect(msg.cache_ttl).to be_nil
    end
  end
end

RSpec.describe KubeMQ::CQ::QueryResponse do
  it 'stores all fields including cache_hit' do
    resp = described_class.new(
      client_id: 'c1', request_id: 'r1',
      executed: true, body: 'result',
      metadata: 'm', cache_hit: true
    )
    expect(resp.cache_hit).to be true
    expect(resp.body).to eq('result')
  end

  it 'defaults cache_hit to false' do
    resp = described_class.new(
      client_id: 'c1', request_id: 'r1', executed: true
    )
    expect(resp.cache_hit).to be false
  end
end

RSpec.describe KubeMQ::CQ::QueryResponseMessage do
  it 'stores all query response fields' do
    msg = described_class.new(
      request_id: 'r1', reply_channel: 'reply-ch',
      executed: true, body: 'result', metadata: 'm'
    )
    expect(msg.request_id).to eq('r1')
    expect(msg.body).to eq('result')
  end
end

RSpec.describe KubeMQ::CQ::QueryReceived do
  it 'stores all fields including reply_channel' do
    received = described_class.new(
      id: 'qr-1', channel: 'q.ch',
      metadata: 'm', body: 'b',
      reply_channel: 'reply-ch', tags: {}
    )
    expect(received.reply_channel).to eq('reply-ch')
  end
end

RSpec.describe KubeMQ::CQ::CommandsSubscription do
  it 'stores channel and group' do
    sub = described_class.new(channel: 'cmd.ch', group: 'g1')
    expect(sub.channel).to eq('cmd.ch')
    expect(sub.group).to eq('g1')
  end

  it 'returns COMMANDS subscribe_type' do
    sub = described_class.new(channel: 'cmd.ch')
    expect(sub.subscribe_type).to eq(KubeMQ::SubscribeType::COMMANDS)
  end
end

RSpec.describe KubeMQ::CQ::QueriesSubscription do
  it 'stores channel and group' do
    sub = described_class.new(channel: 'q.ch', group: 'g1')
    expect(sub.channel).to eq('q.ch')
  end

  it 'returns QUERIES subscribe_type' do
    sub = described_class.new(channel: 'q.ch')
    expect(sub.subscribe_type).to eq(KubeMQ::SubscribeType::QUERIES)
  end
end
