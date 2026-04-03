# frozen_string_literal: true

RSpec.describe KubeMQ::PubSub::EventSender do
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
      msg = KubeMQ::PubSub::EventMessage.new(channel: '', body: 'b')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'validates content' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'pushes proto to request queue' do
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'data')
      result = sender.publish(msg)
      expect(result).to be_nil
    end

    it 'raises ClientClosedError after close' do
      sender.close
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'x')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe '#close' do
    it 'is idempotent' do
      sender.close
      expect { sender.close }.not_to raise_error
    end

    it 'stops accepting messages' do
      sender.close
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b')
      expect { sender.publish(msg) }.to raise_error(KubeMQ::ClientClosedError)
    end
  end

  describe 'on_error callback for stream result errors' do
    it 'invokes on_error when stream result contains error' do
      errors_received = []
      allow(stub_client).to receive(:send_events_stream) do |input_enum|
        Enumerator.new do |y|
          input_enum.each do |_proto|
            y.yield(double('Result', EventID: 'e1', Sent: false, Error: 'publish failed'))
          end
        end
      end
      s = described_class.new(
        transport: transport, client_id: 'test-client',
        on_error: ->(result) { errors_received << result }
      )
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'data')
      s.publish(msg)
      sleep(0.2)
      expect(errors_received.size).to eq(1)
      expect(errors_received.first.Error).to eq('publish failed')
      s.close
    end
  end

  describe 'stream broken handling' do
    it 'marks stream as broken when gRPC error occurs' do
      allow(stub_client).to receive(:send_events_stream).and_raise(GRPC::BadStatus.new(14, 'down'))
      s = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b')
      expect { s.publish(msg) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end

    it 'marks stream as broken on StandardError' do
      allow(stub_client).to receive(:send_events_stream).and_raise(RuntimeError, 'boom')
      s = described_class.new(transport: transport, client_id: 'test-client')
      sleep(0.1)
      msg = KubeMQ::PubSub::EventMessage.new(channel: 'ch', body: 'b')
      expect { s.publish(msg) }.to raise_error(KubeMQ::StreamBrokenError)
      s.close
    end
  end
end
