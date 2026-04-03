# frozen_string_literal: true

RSpec.describe 'CQ Characterization' do
  describe 'CommandMessage edge cases' do
    it 'auto-generates unique IDs' do
      ids = 10.times.map do
        KubeMQ::CQ::CommandMessage.new(channel: 'cmd', timeout: 1000).id
      end
      expect(ids.uniq.size).to eq(10)
    end

    it 'allows nil body and metadata (validation happens at client)' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: 'cmd', timeout: 1000)
      expect(msg.body).to be_nil
      expect(msg.metadata).to be_nil
    end

    it 'tags default to empty hash' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: 'cmd', timeout: 1000)
      expect(msg.tags).to eq({})
    end
  end

  describe 'QueryMessage edge cases' do
    it 'cache_key and cache_ttl default to nil' do
      msg = KubeMQ::CQ::QueryMessage.new(channel: 'q', timeout: 1000)
      expect(msg.cache_key).to be_nil
      expect(msg.cache_ttl).to be_nil
    end

    it 'auto-generates unique IDs' do
      ids = 10.times.map do
        KubeMQ::CQ::QueryMessage.new(channel: 'q', timeout: 1000).id
      end
      expect(ids.uniq.size).to eq(10)
    end
  end

  describe 'CommandResponse edge cases' do
    it 'defaults error to nil and tags to empty hash' do
      resp = KubeMQ::CQ::CommandResponse.new(
        client_id: 'c1', request_id: 'r1', executed: true
      )
      expect(resp.error).to be_nil
      expect(resp.tags).to eq({})
    end
  end

  describe 'QueryResponse edge cases' do
    it 'defaults cache_hit to false' do
      resp = KubeMQ::CQ::QueryResponse.new(
        client_id: 'c1', request_id: 'r1', executed: true
      )
      expect(resp.cache_hit).to be false
    end

    it 'cache_hit=true is preserved' do
      resp = KubeMQ::CQ::QueryResponse.new(
        client_id: 'c1', request_id: 'r1',
        executed: true, cache_hit: true
      )
      expect(resp.cache_hit).to be true
    end
  end

  describe 'CommandResponseMessage' do
    it 'default tags to empty hash' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: 'ch', executed: true
      )
      expect(resp.tags).to eq({})
    end

    it 'stores error message' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: 'ch',
        executed: false, error: 'command failed'
      )
      expect(resp.error).to eq('command failed')
      expect(resp.executed).to be false
    end
  end

  describe 'QueryResponseMessage' do
    it 'stores body and metadata' do
      resp = KubeMQ::CQ::QueryResponseMessage.new(
        request_id: 'r1', reply_channel: 'ch',
        executed: true, body: 'result', metadata: 'done'
      )
      expect(resp.body).to eq('result')
      expect(resp.metadata).to eq('done')
    end
  end

  describe 'Converter request_to_proto' do
    it 'uses COMMAND type for CommandMessage' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'cmd.ch', timeout: 5000, body: 'b'
      )
      proto = KubeMQ::Transport::Converter.request_to_proto(
        msg, 'c1', KubeMQ::RequestType::COMMAND
      )
      expect(proto.RequestTypeData).to eq(:Command)
    end

    it 'uses QUERY type for QueryMessage' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'q.ch', timeout: 5000, body: 'b'
      )
      proto = KubeMQ::Transport::Converter.request_to_proto(
        msg, 'c1', KubeMQ::RequestType::QUERY
      )
      expect(proto.RequestTypeData).to eq(:Query)
    end

    it 'defaults CacheKey and CacheTTL to empty/0 for commands' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'cmd.ch', timeout: 5000, body: 'b'
      )
      proto = KubeMQ::Transport::Converter.request_to_proto(
        msg, 'c1', KubeMQ::RequestType::COMMAND
      )
      expect(proto.CacheKey).to eq('')
      expect(proto.CacheTTL).to eq(0)
    end

    it 'includes timeout in proto' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'cmd.ch', timeout: 7500, body: 'b'
      )
      proto = KubeMQ::Transport::Converter.request_to_proto(
        msg, 'c1', KubeMQ::RequestType::COMMAND
      )
      expect(proto.Timeout).to eq(7500)
    end
  end

  describe 'Converter response_message_to_proto' do
    it 'converts CommandResponseMessage to Response proto' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: 'reply',
        executed: true
      )
      proto = KubeMQ::Transport::Converter.response_message_to_proto(resp, 'c1')
      expect(proto).to be_a(Kubemq::Response)
      expect(proto.Executed).to be true
      expect(proto.Error).to eq('')
    end

    it 'converts QueryResponseMessage with error' do
      resp = KubeMQ::CQ::QueryResponseMessage.new(
        request_id: 'r2', reply_channel: 'reply',
        executed: false, error: 'query failed'
      )
      proto = KubeMQ::Transport::Converter.response_message_to_proto(resp, 'c1')
      expect(proto.Executed).to be false
      expect(proto.Error).to eq('query failed')
    end
  end

  describe 'SubscribeType constants' do
    it 'COMMANDS = 3' do
      expect(KubeMQ::SubscribeType::COMMANDS).to eq(3)
    end

    it 'QUERIES = 4' do
      expect(KubeMQ::SubscribeType::QUERIES).to eq(4)
    end
  end

  describe 'CommandsSubscription' do
    it 'subscribe_type returns COMMANDS' do
      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'ch')
      expect(sub.subscribe_type).to eq(KubeMQ::SubscribeType::COMMANDS)
    end
  end

  describe 'QueriesSubscription' do
    it 'subscribe_type returns QUERIES' do
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'ch')
      expect(sub.subscribe_type).to eq(KubeMQ::SubscribeType::QUERIES)
    end
  end
end
