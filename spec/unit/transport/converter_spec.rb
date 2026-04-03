# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::Converter do
  describe '.event_to_proto' do
    let(:message) do
      KubeMQ::PubSub::EventMessage.new(
        channel: 'events.test',
        metadata: 'test-meta',
        body: 'test-body',
        tags: { 'key' => 'val' },
        id: 'evt-1'
      )
    end

    it 'converts EventMessage to Kubemq::Event proto' do
      proto = described_class.event_to_proto(message, 'client-1')
      expect(proto).to be_a(Kubemq::Event)
      expect(proto.EventID).to eq('evt-1')
      expect(proto.ClientID).to eq('client-1')
      expect(proto.Channel).to eq('events.test')
      expect(proto.Metadata).to eq('test-meta')
      expect(proto.Store).to be false
    end

    it 'sets Store to true when store: true' do
      proto = described_class.event_to_proto(message, 'client-1', store: true)
      expect(proto.Store).to be true
    end

    it 'auto-generates UUID when id is nil' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b', id: nil)
      msg.id = nil
      proto = described_class.event_to_proto(msg, 'c1')
      expect(proto.EventID).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'encodes body to ASCII-8BIT' do
      proto = described_class.event_to_proto(message, 'c1')
      expect(proto.Body.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'converts tags to proto map' do
      proto = described_class.event_to_proto(message, 'c1')
      expect(proto.Tags['key']).to eq('val')
    end
  end

  describe '.proto_to_event_result' do
    it 'extracts id, sent, and error' do
      result = double('Result', EventID: 'e1', Sent: true, Error: '')
      hash = described_class.proto_to_event_result(result)
      expect(hash[:id]).to eq('e1')
      expect(hash[:sent]).to be true
      expect(hash[:error]).to be_nil
    end

    it 'preserves error message when present' do
      result = double('Result', EventID: 'e2', Sent: false, Error: 'oops')
      hash = described_class.proto_to_event_result(result)
      expect(hash[:error]).to eq('oops')
    end
  end

  describe '.proto_to_event_received' do
    it 'extracts all fields from EventReceive proto' do
      proto = double('EventReceive',
                     EventID: 'ev-1', Channel: 'ch', Metadata: 'meta',
                     Body: 'body'.b, Timestamp: 12_345, Sequence: 1,
                     Tags: { 'k' => 'v' })
      hash = described_class.proto_to_event_received(proto)
      expect(hash[:id]).to eq('ev-1')
      expect(hash[:channel]).to eq('ch')
      expect(hash[:sequence]).to eq(1)
      expect(hash[:tags]).to eq({ 'k' => 'v' })
    end
  end

  describe '.queue_message_to_proto' do
    let(:message) do
      KubeMQ::Queues::QueueMessage.new(
        channel: 'q.test',
        metadata: 'qmeta',
        body: 'qbody',
        id: 'qm-1'
      )
    end

    it 'converts QueueMessage to proto' do
      proto = described_class.queue_message_to_proto(message, 'client-1')
      expect(proto).to be_a(Kubemq::QueueMessage)
      expect(proto.MessageID).to eq('qm-1')
      expect(proto.Channel).to eq('q.test')
    end

    it 'converts policy when present' do
      policy = KubeMQ::Queues::QueueMessagePolicy.new(
        expiration_seconds: 60,
        delay_seconds: 5,
        max_receive_count: 3,
        max_receive_queue: 'dlq'
      )
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', body: 'b', policy: policy)
      proto = described_class.queue_message_to_proto(msg, 'c1')
      expect(proto.Policy.ExpirationSeconds).to eq(60)
      expect(proto.Policy.DelaySeconds).to eq(5)
    end
  end

  describe '.request_to_proto' do
    it 'converts CommandMessage to proto' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'cmd.ch', timeout: 5000,
        metadata: 'm', body: 'b', id: 'cmd-1'
      )
      proto = described_class.request_to_proto(msg, 'c1', KubeMQ::RequestType::COMMAND)
      expect(proto.RequestID).to eq('cmd-1')
      expect(proto.RequestTypeData).to eq(:Command)
      expect(proto.Timeout).to eq(5000)
    end

    it 'converts QueryMessage with cache fields' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'q.ch', timeout: 5000,
        metadata: 'm', body: 'b',
        cache_key: 'ck', cache_ttl: 60
      )
      proto = described_class.request_to_proto(msg, 'c1', KubeMQ::RequestType::QUERY)
      expect(proto.CacheKey).to eq('ck')
      expect(proto.CacheTTL).to eq(60)
    end
  end

  describe '.proto_to_command_response' do
    it 'extracts response fields' do
      resp = double('Response',
                    ClientID: 'c1', RequestID: 'r1', Executed: true,
                    Timestamp: 100, Error: '', Tags: { 'a' => 'b' })
      hash = described_class.proto_to_command_response(resp)
      expect(hash[:executed]).to be true
      expect(hash[:error]).to be_nil
    end
  end

  describe '.proto_to_query_response' do
    it 'includes cache_hit field' do
      resp = double('Response',
                    ClientID: 'c1', RequestID: 'r1', Executed: true,
                    Metadata: 'm', Body: 'b', CacheHit: true,
                    Timestamp: 100, Error: '', Tags: {})
      hash = described_class.proto_to_query_response(resp)
      expect(hash[:cache_hit]).to be true
    end
  end

  describe '.response_message_to_proto' do
    it 'converts CommandResponseMessage to proto' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: 'reply-ch',
        executed: true
      )
      proto = described_class.response_message_to_proto(resp, 'c1')
      expect(proto).to be_a(Kubemq::Response)
      expect(proto.RequestID).to eq('r1')
      expect(proto.Executed).to be true
    end
  end

  describe '.subscribe_to_proto' do
    it 'raises ArgumentError for unknown subscribe_type' do
      sub = double('Subscription', channel: 'ch', subscribe_type: 999, group: '')
      expect { described_class.subscribe_to_proto(sub, 'c1') }
        .to raise_error(ArgumentError, /Unknown subscribe_type/)
    end
  end

  describe '.proto_to_queue_message_received' do
    it 'converts proto with Attributes' do
      attrs = double('Attrs',
                     Timestamp: 100, Sequence: 5, MD5OfBody: 'abc',
                     ReceiveCount: 2, ReRouted: true,
                     ReRoutedFromQueue: 'original-q',
                     ExpirationAt: 999, DelayedTo: 0)
      msg = double('QueueMsg',
                   MessageID: 'qm-1', Channel: 'q.ch',
                   Metadata: 'meta', Body: 'body'.b,
                   Tags: { 'k' => 'v' }, Attributes: attrs)
      allow(msg).to receive_message_chain(:Tags, :to_h).and_return({ 'k' => 'v' })

      result = described_class.proto_to_queue_message_received(msg)
      expect(result[:id]).to eq('qm-1')
      expect(result[:channel]).to eq('q.ch')
      expect(result[:attributes][:sequence]).to eq(5)
      expect(result[:attributes][:re_routed]).to be true
    end

    it 'returns nil attributes when Attributes is nil' do
      msg = double('QueueMsg',
                   MessageID: 'qm-2', Channel: 'q.ch',
                   Metadata: '', Body: ''.b,
                   Tags: {}, Attributes: nil)
      allow(msg).to receive_message_chain(:Tags, :to_h).and_return({})

      result = described_class.proto_to_queue_message_received(msg)
      expect(result[:id]).to eq('qm-2')
      expect(result[:attributes]).to be_nil
    end
  end

  describe '.encode_body' do
    it 'returns empty binary string for nil' do
      result = described_class.encode_body(nil)
      expect(result).to eq(''.b)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'forces encoding to ASCII-8BIT for strings' do
      result = described_class.encode_body('hello')
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'raises ArgumentError for non-string body' do
      expect { described_class.encode_body(42) }.to raise_error(ArgumentError, /body must be a String/)
    end
  end
end
