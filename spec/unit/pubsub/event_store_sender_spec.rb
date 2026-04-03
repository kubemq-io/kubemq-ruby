# frozen_string_literal: true

RSpec.describe KubeMQ::PubSub::EventStoreSender do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(KubeMQ::Transport::GrpcTransport, kubemq_client: stub_client)
  end

  before do
    allow(stub_client).to receive(:send_events_stream) do |_enum|
      [].each
    end
  end

  subject(:sender) do
    described_class.new(transport: transport, client_id: 'test-client')
  end

  after { sender.close }

  describe '#send' do
    it 'validates channel' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: '', body: 'b')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates content' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'ch')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'raises ClientClosedError after close' do
      sender.close
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'ch', body: 'x')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ClientClosedError)
    end

    it 'raises TimeoutError when no response received' do
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'ch', body: 'data')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::TimeoutError)
    end

    context 'with a responding stream' do
      let(:event_id) { nil }

      before do
        allow(stub_client).to receive(:send_events_stream) do |input_enum|
          Enumerator.new do |y|
            input_enum.each do |proto|
              y.yield(double('Result', EventID: proto.EventID, Sent: true, Error: ''))
            end
          end
        end
      end

      it 'returns EventStoreResult on successful send' do
        msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'es.ch', body: 'hello')
        s = described_class.new(transport: transport, client_id: 'test-client')
        result = s.publish(msg)
        expect(result).to be_a(KubeMQ::PubSub::EventStoreResult)
        expect(result.sent).to be true
        s.close
      end

      it 'returns error from result when present' do
        allow(stub_client).to receive(:send_events_stream) do |input_enum|
          Enumerator.new do |y|
            input_enum.each do |proto|
              y.yield(double('Result', EventID: proto.EventID, Sent: false, Error: 'server error'))
            end
          end
        end
        msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'es.ch', body: 'data')
        s = described_class.new(transport: transport, client_id: 'test-client')
        result = s.publish(msg)
        expect(result.error).to eq('server error')
        s.close
      end
    end
  end

  describe '#close' do
    it 'is idempotent' do
      sender.close
      expect { sender.close }.not_to raise_error
    end

    it 'stops accepting messages' do
      sender.close
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'ch', body: 'b')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe 'stream broken handling' do
    it 'marks stream as broken when gRPC error occurs' do
      allow(stub_client).to receive(:send_events_stream).and_raise(GRPC::BadStatus.new(14, 'down'))
      s = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'ch', body: 'b')
      expect { s.publish(msg) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end

    it 'raises StreamBrokenError when stream dies during wait for response' do
      call_count = 0
      allow(stub_client).to receive(:send_events_stream) do |input_enum|
        Enumerator.new do |_y|
          input_enum.each do |_proto|
            call_count += 1
            raise GRPC::Unavailable.new('gone') if call_count >= 1
          end
        end
      end
      allow(transport).to receive(:on_disconnect!)
      s = described_class.new(transport: transport, client_id: 'test-client')
      msg = KubeMQ::PubSub::EventStoreMessage.new(channel: 'es.ch', body: 'data')
      expect { s.publish(msg) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end
  end
end
