# frozen_string_literal: true

RSpec.describe KubeMQ::Telemetry do
  describe '.otel_available?' do
    it 'returns falsy when OpenTelemetry is not defined' do
      expect(described_class.otel_available?).to be_falsey
    end
  end

  describe '.with_span' do
    context 'when OpenTelemetry is not available' do
      before { allow(described_class).to receive(:otel_available?).and_return(false) }

      it 'yields nil and returns block result' do
        result = described_class.with_span('test op') { |span| span.nil? ? :no_span : :has_span }
        expect(result).to eq(:no_span)
      end

      it 'raises ArgumentError without a block' do
        expect { described_class.with_span('test') }.to raise_error(ArgumentError, /block required/)
      end
    end

    context 'when OpenTelemetry is available' do
      let(:tracer) { double('tracer') }
      let(:tracer_provider) { double('tracer_provider') }

      before do
        allow(described_class).to receive(:otel_available?).and_return(true)
        stub_const('OpenTelemetry', double('OpenTelemetry', tracer_provider: tracer_provider))
        allow(tracer_provider).to receive(:tracer).with('kubemq-ruby').and_return(tracer)
        allow(tracer).to receive(:in_span).and_yield(double('span'))
      end

      it 'creates a span with messaging.system attribute' do
        expect(tracer).to receive(:in_span).with(
          'test op',
          hash_including(
            attributes: hash_including(
              'messaging.system' => 'kubemq'
            )
          )
        )
        described_class.with_span('test op') { |_span| :ok }
      end

      it 'merges custom attributes' do
        expect(tracer).to receive(:in_span).with(
          'send event',
          hash_including(
            attributes: hash_including(
              'messaging.system' => 'kubemq',
              'custom.key' => 'val'
            )
          )
        )
        described_class.with_span('send event', attributes: { 'custom.key' => 'val' }) { |_| :ok }
      end

      it 'passes kind to in_span' do
        expect(tracer).to receive(:in_span).with(
          'produce', hash_including(kind: :producer)
        )
        described_class.with_span('produce', kind: :producer) { |_| :ok }
      end

      it 'stringifies attribute keys' do
        expect(tracer).to receive(:in_span).with(
          'op',
          hash_including(
            attributes: hash_including('sym_key' => 'v')
          )
        )
        described_class.with_span('op', attributes: { sym_key: 'v' }) { |_| :ok }
      end
    end
  end
end

RSpec.describe KubeMQ::Telemetry::SemanticConventions do
  it 'defines MESSAGING_SYSTEM' do
    expect(described_class::MESSAGING_SYSTEM).to eq('kubemq')
  end

  it 'defines attribute keys' do
    expect(described_class::ATTR_MESSAGING_SYSTEM).to eq('messaging.system')
    expect(described_class::ATTR_MESSAGING_OPERATION_NAME).to eq('messaging.operation.name')
    expect(described_class::ATTR_MESSAGING_DESTINATION_NAME).to eq('messaging.destination.name')
    expect(described_class::ATTR_MESSAGING_MESSAGE_ID).to eq('messaging.message.id')
    expect(described_class::ATTR_MESSAGING_CLIENT_ID).to eq('messaging.client.id')
  end

  it 'defines span kinds' do
    expect(described_class::SPAN_KIND_PRODUCER).to eq(:producer)
    expect(described_class::SPAN_KIND_CONSUMER).to eq(:consumer)
    expect(described_class::SPAN_KIND_CLIENT).to eq(:client)
  end
end
