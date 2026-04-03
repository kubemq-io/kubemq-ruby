# frozen_string_literal: true

RSpec.describe KubeMQ::Queues::DownstreamReceiver do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(KubeMQ::Transport::GrpcTransport, kubemq_client: stub_client)
  end

  before do
    allow(stub_client).to receive(:queues_downstream) do |_enum|
      [].each
    end
  end

  subject(:receiver) do
    described_class.new(transport: transport, client_id: 'test-client')
  end

  after { receiver.close }

  describe '#poll' do
    it 'validates channel' do
      req = KubeMQ::Queues::QueuePollRequest.new(channel: '', max_items: 1)
      expect { receiver.poll(req) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates max_items >= 1' do
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 0)
      expect { receiver.poll(req) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates wait_timeout <= 3600' do
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', wait_timeout: 3601)
      expect { receiver.poll(req) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'raises ClientClosedError after close' do
      receiver.close
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch')
      expect { receiver.poll(req) }.to raise_error(KubeMQ::ClientClosedError)
    end

    it 'raises TimeoutError when no response received' do
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 1, wait_timeout: 1)
      expect { receiver.poll(req) }.to raise_error(KubeMQ::TimeoutError)
    end
  end

  describe '#poll when stream is broken' do
    it 'raises StreamBrokenError when stream is not alive' do
      receiver.instance_variable_set(:@stream_alive, false)
      receiver.instance_variable_set(:@stream_error, RuntimeError.new('connection lost'))
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 1, wait_timeout: 1)
      expect { receiver.poll(req) }.to raise_error(KubeMQ::StreamBrokenError, /downstream stream is broken/)
    end
  end

  describe 'stream error handling' do
    it 'marks stream as broken and wakes pending waiters on gRPC error' do
      allow(transport).to receive(:on_disconnect!)
      allow(stub_client).to receive(:queues_downstream).and_raise(GRPC::Unavailable.new('server down'))
      r = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      expect(r.instance_variable_get(:@stream_alive)).to be false
      expect(r.instance_variable_get(:@stream_error)).to be_a(GRPC::Unavailable)
      r.close
    end

    it 'marks stream as broken on StandardError' do
      allow(stub_client).to receive(:queues_downstream).and_raise(RuntimeError, 'unexpected')
      r = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      expect(r.instance_variable_get(:@stream_alive)).to be false
      r.close
    end
  end

  describe '#send_action' do
    it 'sends an action request to the stream' do
      receiver.send_action(
        transaction_id: 'tx-1',
        type: :AckAll
      )
    end

    it 'raises ClientClosedError when closed' do
      receiver.close
      expect do
        receiver.send_action(transaction_id: 'tx-1', type: :AckAll)
      end.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe '#close' do
    it 'is idempotent' do
      receiver.close
      expect { receiver.close }.not_to raise_error
    end
  end

  describe 'successful poll with responding stream' do
    let(:proto_msg) do
      attrs = double('Attributes',
                     Timestamp: 100, Sequence: 1, MD5OfBody: 'md5',
                     ReceiveCount: 1, ReRouted: false,
                     ReRoutedFromQueue: '', ExpirationAt: 0, DelayedTo: 0)
      double('QueueMessage',
             MessageID: 'qm-1', Channel: 'q.ch',
             Metadata: 'meta', Body: 'body',
             Tags: {}, Attributes: attrs, Policy: nil)
    end

    before do
      allow(KubeMQ::Transport::Converter).to receive(:proto_to_queue_message_received)
        .and_return({
                      id: 'qm-1', channel: 'q.ch', metadata: 'meta',
                      body: 'body', tags: {},
                      attributes: { timestamp: 100, sequence: 1 }
                    })
      allow(stub_client).to receive(:queues_downstream) do |input_enum|
        Enumerator.new do |y|
          input_enum.each do |proto_req|
            y.yield(double('DownstreamResponse',
                           RefRequestId: proto_req.RequestID,
                           TransactionId: 'tx-1',
                           Messages: [proto_msg],
                           IsError: false, Error: '',
                           ActiveOffsets: [1],
                           TransactionComplete: false))
          end
        end
      end
    end

    it 'returns QueuePollResponse with messages' do
      r = described_class.new(transport: transport, client_id: 'test-client')
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 1, wait_timeout: 5)
      result = r.poll(req)
      expect(result).to be_a(KubeMQ::Queues::QueuePollResponse)
      expect(result.transaction_id).to eq('tx-1')
      expect(result.messages.size).to eq(1)
      r.close
    end
  end
end
