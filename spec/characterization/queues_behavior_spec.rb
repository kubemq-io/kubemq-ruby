# frozen_string_literal: true

RSpec.describe 'Queues Characterization' do
  describe 'QueueMessage edge cases' do
    it 'auto-generates unique IDs for each message' do
      ids = 10.times.map { KubeMQ::Queues::QueueMessage.new(channel: 'q').id }
      expect(ids.uniq.size).to eq(10)
    end

    it 'handles nil body in conversion' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', metadata: 'm')
      proto = KubeMQ::Transport::Converter.queue_message_to_proto(msg, 'c1')
      expect(proto.Body).to eq(''.b)
    end

    it 'converts policy with zero defaults' do
      policy = KubeMQ::Queues::QueueMessagePolicy.new
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', body: 'b', policy: policy)
      proto = KubeMQ::Transport::Converter.queue_message_to_proto(msg, 'c1')
      expect(proto.Policy.ExpirationSeconds).to eq(0)
      expect(proto.Policy.DelaySeconds).to eq(0)
    end

    it 'omits policy when nil' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', body: 'b')
      proto = KubeMQ::Transport::Converter.queue_message_to_proto(msg, 'c1')
      expect(proto.Policy).to be_nil
    end
  end

  describe 'QueueSendResult behavior' do
    it 'error? returns false for nil error' do
      result = KubeMQ::Queues::QueueSendResult.new(id: 'x', error: nil)
      expect(result).not_to be_error
    end

    it 'error? returns false for empty string error' do
      result = KubeMQ::Queues::QueueSendResult.new(id: 'x', error: '')
      expect(result).not_to be_error
    end

    it 'error? returns true for non-empty error' do
      result = KubeMQ::Queues::QueueSendResult.new(id: 'x', error: 'fail')
      expect(result).to be_error
    end
  end

  describe 'QueuePollResponse behavior' do
    it 'error? returns false when error is nil' do
      resp = KubeMQ::Queues::QueuePollResponse.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false
      )
      expect(resp).not_to be_error
    end

    it 'error? returns true when error is non-empty' do
      resp = KubeMQ::Queues::QueuePollResponse.new(
        transaction_id: 't', messages: [], error: 'err',
        active_offsets: [], transaction_complete: false
      )
      expect(resp).to be_error
    end

    it 'transaction_status returns false when transaction_complete' do
      resp = KubeMQ::Queues::QueuePollResponse.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: true
      )
      expect(resp.transaction_status).to be false
    end

    it 'transaction_status returns false without action_proc' do
      resp = KubeMQ::Queues::QueuePollResponse.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false
      )
      expect(resp.transaction_status).to be false
    end
  end

  describe 'QueueMessageReceived transaction actions' do
    it 'ack raises TransactionError without bound receiver' do
      msg = KubeMQ::Queues::QueueMessageReceived.new(
        id: 'q1', channel: 'ch', metadata: '',
        body: 'b', tags: {}
      )
      expect { msg.ack }.to raise_error(KubeMQ::TransactionError, /No downstream/)
    end

    it 'reject raises TransactionError without bound receiver' do
      msg = KubeMQ::Queues::QueueMessageReceived.new(
        id: 'q1', channel: 'ch', metadata: '',
        body: 'b', tags: {}
      )
      expect { msg.reject }.to raise_error(KubeMQ::TransactionError, /No downstream/)
    end

    it 'requeue raises TransactionError without bound receiver' do
      msg = KubeMQ::Queues::QueueMessageReceived.new(
        id: 'q1', channel: 'ch', metadata: '',
        body: 'b', tags: {}
      )
      expect { msg.requeue(channel: 'dlq') }.to raise_error(KubeMQ::TransactionError)
    end
  end

  describe 'QueueMessageAttributes' do
    it 'stores all attribute fields' do
      attrs = KubeMQ::Queues::QueueMessageAttributes.new(
        timestamp: 100, sequence: 5, md5_of_body: 'abc',
        receive_count: 2, re_routed: true,
        re_routed_from_queue: 'original', expiration_at: 200,
        delayed_to: 300
      )
      expect(attrs.timestamp).to eq(100)
      expect(attrs.sequence).to eq(5)
      expect(attrs.re_routed).to be true
      expect(attrs.re_routed_from_queue).to eq('original')
    end
  end

  describe 'DownstreamRequestType constants' do
    it 'defines all request types' do
      expect(KubeMQ::Queues::DownstreamRequestType::GET).to eq(1)
      expect(KubeMQ::Queues::DownstreamRequestType::ACK_ALL).to eq(2)
      expect(KubeMQ::Queues::DownstreamRequestType::CLOSE_BY_CLIENT).to eq(10)
      expect(KubeMQ::Queues::DownstreamRequestType::CLOSE_BY_SERVER).to eq(11)
    end
  end
end
