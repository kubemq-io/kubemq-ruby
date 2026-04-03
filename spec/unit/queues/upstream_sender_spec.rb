# frozen_string_literal: true

RSpec.describe KubeMQ::Queues::UpstreamSender do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(KubeMQ::Transport::GrpcTransport, kubemq_client: stub_client)
  end

  before do
    allow(stub_client).to receive(:queues_upstream) do |_enum|
      [].each
    end
  end

  subject(:sender) do
    described_class.new(transport: transport, client_id: 'test-client')
  end

  after { sender.close }

  describe '#send' do
    it 'validates channel for each message' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: '', body: 'data')
      expect { sender.publish([msg]) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'raises ClientClosedError after close' do
      sender.close
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', body: 'data')
      expect { sender.publish([msg]) }.to raise_error(KubeMQ::ClientClosedError)
    end

    it 'wraps single message in array' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.test', body: 'data')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::TimeoutError)
    end

    it 'raises TimeoutError when no response received' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.test', body: 'data')
      expect { sender.publish([msg]) }.to raise_error(KubeMQ::TimeoutError)
    end
  end

  describe '#close' do
    it 'is idempotent' do
      sender.close
      expect { sender.close }.not_to raise_error
    end

    it 'prevents further sends' do
      sender.close
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q', body: 'b')
      expect { sender.publish([msg]) }.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe 'stream broken handling' do
    it 'marks stream as broken when gRPC error occurs' do
      allow(stub_client).to receive(:queues_upstream).and_raise(GRPC::BadStatus.new(14, 'down'))
      s = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'b')
      expect { s.publish([msg]) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end

    it 'raises StreamBrokenError when stream dies during wait' do
      call_count = 0
      allow(stub_client).to receive(:queues_upstream) do |input_enum|
        Enumerator.new do |_y|
          input_enum.each do |_proto_req|
            call_count += 1
            raise GRPC::Unavailable.new('gone') if call_count >= 1
          end
        end
      end
      allow(transport).to receive(:on_disconnect!)
      s = described_class.new(transport: transport, client_id: 'test-client')
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      expect { s.publish([msg]) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end
  end

  describe 'successful send with responding stream' do
    before do
      allow(stub_client).to receive(:queues_upstream) do |input_enum|
        Enumerator.new do |y|
          input_enum.each do |proto_req|
            result = double('QueueResult',
                            MessageID: 'qm-1', SentAt: 100,
                            ExpirationAt: 0, DelayedTo: 0,
                            IsError: false, Error: '')
            y.yield(double('Response',
                           RefRequestID: proto_req.RequestID,
                           IsError: false, Error: '',
                           Results: [result]))
          end
        end
      end
    end

    it 'returns QueueSendResult array' do
      s = described_class.new(transport: transport, client_id: 'test-client')
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      results = s.publish([msg])
      expect(results.size).to eq(1)
      expect(results.first).to be_a(KubeMQ::Queues::QueueSendResult)
      expect(results.first.id).to eq('qm-1')
      s.close
    end

    it 'raises MessageError when response has error' do
      allow(stub_client).to receive(:queues_upstream) do |input_enum|
        Enumerator.new do |y|
          input_enum.each do |proto_req|
            y.yield(double('Response',
                           RefRequestID: proto_req.RequestID,
                           IsError: true, Error: 'queue full',
                           Results: []))
          end
        end
      end
      s = described_class.new(transport: transport, client_id: 'test-client')
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      expect { s.publish([msg]) }.to raise_error(KubeMQ::MessageError, /queue full/)
      s.close
    end
  end
end
