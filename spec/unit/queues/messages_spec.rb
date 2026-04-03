# frozen_string_literal: true

RSpec.describe KubeMQ::Queues::QueueMessage do
  describe '#initialize' do
    it 'auto-generates UUID for id' do
      msg = described_class.new(channel: 'q.test')
      expect(msg.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'uses provided id' do
      msg = described_class.new(channel: 'q.test', id: 'qm-1')
      expect(msg.id).to eq('qm-1')
    end

    it 'defaults tags to empty hash' do
      msg = described_class.new(channel: 'q.test')
      expect(msg.tags).to eq({})
    end

    it 'defaults policy to nil' do
      msg = described_class.new(channel: 'q.test')
      expect(msg.policy).to be_nil
    end

    it 'accepts policy' do
      policy = KubeMQ::Queues::QueueMessagePolicy.new(expiration_seconds: 60)
      msg = described_class.new(channel: 'q.test', policy: policy)
      expect(msg.policy.expiration_seconds).to eq(60)
    end
  end
end

RSpec.describe KubeMQ::Queues::QueueMessagePolicy do
  it 'stores all policy fields' do
    policy = described_class.new(
      expiration_seconds: 120,
      delay_seconds: 10,
      max_receive_count: 5,
      max_receive_queue: 'dlq'
    )
    expect(policy.expiration_seconds).to eq(120)
    expect(policy.delay_seconds).to eq(10)
    expect(policy.max_receive_count).to eq(5)
    expect(policy.max_receive_queue).to eq('dlq')
  end

  it 'defaults all fields to zero/empty' do
    policy = described_class.new
    expect(policy.expiration_seconds).to eq(0)
    expect(policy.delay_seconds).to eq(0)
    expect(policy.max_receive_count).to eq(0)
    expect(policy.max_receive_queue).to eq('')
  end
end

RSpec.describe KubeMQ::Queues::QueueSendResult do
  it 'stores result fields' do
    result = described_class.new(id: 'qs-1', sent_at: 100, error: nil)
    expect(result.id).to eq('qs-1')
    expect(result.sent_at).to eq(100)
    expect(result.error).to be_nil
  end

  describe '#error?' do
    it 'returns false on success' do
      result = described_class.new(id: 'qs-1', error: nil)
      expect(result).not_to be_error
    end

    it 'returns true on server error' do
      result = described_class.new(id: 'qs-2', error: 'some error')
      expect(result).to be_error
    end

    it 'returns false for empty error string' do
      result = described_class.new(id: 'qs-3', error: '')
      expect(result).not_to be_error
    end
  end
end

RSpec.describe KubeMQ::Queues::QueueMessageReceived do
  let(:action_proc) { ->(_type, **_kw) {} }

  it 'stores all fields' do
    received = described_class.new(
      id: 'qr-1', channel: 'q.ch', metadata: 'm',
      body: 'b', tags: { 'k' => 'v' }
    )
    expect(received.id).to eq('qr-1')
    expect(received.channel).to eq('q.ch')
    expect(received.tags).to eq({ 'k' => 'v' })
  end

  describe '#ack' do
    it 'raises TransactionError without action_proc' do
      received = described_class.new(
        id: 'qr-1', channel: 'ch', metadata: '',
        body: 'b', tags: {}
      )
      expect { received.ack }.to raise_error(KubeMQ::TransactionError)
    end

    it 'calls action_proc with AckRange' do
      called_with = nil
      proc = ->(type, **kw) { called_with = [type, kw] }
      received = described_class.new(
        id: 'qr-1', channel: 'ch', metadata: '',
        body: 'b', tags: {}, action_proc: proc, sequence: 5
      )
      received.ack
      expect(called_with[0]).to eq(:AckRange)
      expect(called_with[1][:sequence_range]).to eq([5])
    end
  end

  describe '#reject' do
    it 'calls action_proc with NAckRange' do
      called_with = nil
      proc = ->(type, **kw) { called_with = [type, kw] }
      received = described_class.new(
        id: 'qr-1', channel: 'ch', metadata: '',
        body: 'b', tags: {}, action_proc: proc, sequence: 7
      )
      received.reject
      expect(called_with[0]).to eq(:NAckRange)
    end
  end

  describe '#requeue' do
    it 'calls action_proc with ReQueueRange and channel' do
      called_with = nil
      proc = ->(type, **kw) { called_with = [type, kw] }
      received = described_class.new(
        id: 'qr-1', channel: 'ch', metadata: '',
        body: 'b', tags: {}, action_proc: proc, sequence: 3
      )
      received.requeue(channel: 'dlq')
      expect(called_with[0]).to eq(:ReQueueRange)
      expect(called_with[1][:channel]).to eq('dlq')
    end
  end
end

RSpec.describe KubeMQ::Queues::QueuePollRequest do
  it 'stores poll parameters' do
    req = described_class.new(channel: 'q.ch', max_items: 10, wait_timeout: 30, auto_ack: true)
    expect(req.channel).to eq('q.ch')
    expect(req.max_items).to eq(10)
    expect(req.wait_timeout).to eq(30)
    expect(req.auto_ack).to be true
  end

  it 'defaults max_items to 1 and auto_ack to false' do
    req = described_class.new(channel: 'q.ch')
    expect(req.max_items).to eq(1)
    expect(req.auto_ack).to be false
  end
end

RSpec.describe KubeMQ::Queues::QueuePollResponse do
  let(:action_proc) { ->(_type, **_kw) {} }

  it 'stores response fields' do
    resp = described_class.new(
      transaction_id: 'tx-1', messages: [],
      error: nil, active_offsets: [1, 2],
      transaction_complete: false, action_proc: action_proc
    )
    expect(resp.transaction_id).to eq('tx-1')
    expect(resp.messages).to eq([])
    expect(resp.active_offsets).to eq([1, 2])
  end

  describe '#error?' do
    it 'returns false when error is nil' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false
      )
      expect(resp).not_to be_error
    end

    it 'returns true when error is present' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: 'err',
        active_offsets: [], transaction_complete: false
      )
      expect(resp).to be_error
    end
  end

  describe 'transaction actions' do
    it '#ack_all sends AckAll action' do
      called = nil
      proc = lambda { |type, **_kw|
        called = type
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.ack_all
      expect(called).to eq(:AckAll)
    end

    it '#nack_all sends NAckAll action' do
      called = nil
      proc = lambda { |type, **_kw|
        called = type
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.nack_all
      expect(called).to eq(:NAckAll)
    end

    it '#ack_range sends AckRange with sequence_range' do
      called_with = nil
      proc = lambda { |type, **kw|
        called_with = [type, kw]
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.ack_range(sequence_range: [1, 2, 3])
      expect(called_with[0]).to eq(:AckRange)
      expect(called_with[1][:sequence_range]).to eq([1, 2, 3])
    end

    it '#nack_range sends NAckRange with sequence_range' do
      called_with = nil
      proc = lambda { |type, **kw|
        called_with = [type, kw]
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.nack_range(sequence_range: [4, 5])
      expect(called_with[0]).to eq(:NAckRange)
    end

    it '#requeue_all sends ReQueueAll with channel' do
      called_with = nil
      proc = lambda { |type, **kw|
        called_with = [type, kw]
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.requeue_all(channel: 'dlq')
      expect(called_with[0]).to eq(:ReQueueAll)
      expect(called_with[1][:channel]).to eq('dlq')
    end

    it '#requeue_range sends ReQueueRange with channel and sequence_range' do
      called_with = nil
      proc = lambda { |type, **kw|
        called_with = [type, kw]
        nil
      }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      resp.requeue_range(channel: 'dlq', sequence_range: [1])
      expect(called_with[0]).to eq(:ReQueueRange)
      expect(called_with[1][:channel]).to eq('dlq')
      expect(called_with[1][:sequence_range]).to eq([1])
    end

    it 'raises TransactionError when no action_proc' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false
      )
      expect { resp.ack_all }.to raise_error(KubeMQ::TransactionError)
    end

    it 'raises TransactionError when action response has error' do
      error_response = double('response', IsError: true, Error: 'action failed')
      proc = ->(_type, **_kw) { error_response }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      expect { resp.ack_all }.to raise_error(KubeMQ::TransactionError, /action failed/)
    end

    it '#transaction_status returns false when transaction_complete is true' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: true,
        action_proc: ->(_type, **_kw) {}
      )
      expect(resp.transaction_status).to be false
    end

    it '#transaction_status returns false when no action_proc' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false
      )
      expect(resp.transaction_status).to be false
    end

    it '#transaction_status queries action_proc for status' do
      status_resp = double('StatusResp', TransactionComplete: false)
      proc = ->(_type, **_kw) { status_resp }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      expect(resp.transaction_status).to be true
    end

    it '#transaction_status returns false when TransactionComplete is true' do
      status_resp = double('StatusResp', TransactionComplete: true)
      proc = ->(_type, **_kw) { status_resp }
      resp = described_class.new(
        transaction_id: 't', messages: [], error: nil,
        active_offsets: [], transaction_complete: false,
        action_proc: proc
      )
      expect(resp.transaction_status).to be false
    end
  end

  describe '#error? edge cases' do
    it 'returns false when error is empty string' do
      resp = described_class.new(
        transaction_id: 't', messages: [], error: '',
        active_offsets: [], transaction_complete: false
      )
      expect(resp).not_to be_error
    end
  end
end

RSpec.describe KubeMQ::Queues::QueueMessageAttributes do
  it 'stores all attribute fields' do
    attrs = described_class.new(
      timestamp: 100, sequence: 5, md5_of_body: 'abc',
      receive_count: 2, re_routed: true, re_routed_from_queue: 'orig',
      expiration_at: 200, delayed_to: 50
    )
    expect(attrs.timestamp).to eq(100)
    expect(attrs.sequence).to eq(5)
    expect(attrs.md5_of_body).to eq('abc')
    expect(attrs.receive_count).to eq(2)
    expect(attrs.re_routed).to be true
    expect(attrs.re_routed_from_queue).to eq('orig')
    expect(attrs.expiration_at).to eq(200)
    expect(attrs.delayed_to).to eq(50)
  end

  it 'has sensible defaults' do
    attrs = described_class.new
    expect(attrs.timestamp).to eq(0)
    expect(attrs.sequence).to eq(0)
    expect(attrs.md5_of_body).to eq('')
    expect(attrs.receive_count).to eq(0)
    expect(attrs.re_routed).to be false
    expect(attrs.re_routed_from_queue).to eq('')
    expect(attrs.expiration_at).to eq(0)
    expect(attrs.delayed_to).to eq(0)
  end
end
