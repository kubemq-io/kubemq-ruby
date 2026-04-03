# frozen_string_literal: true

RSpec.describe KubeMQ::Interceptors::MetricsInterceptor do
  let(:request) { double('request') }
  let(:call) { double('call') }
  let(:method) { '/kubemq.Kubemq/SendEvent' }
  let(:metadata) { {} }

  describe 'when OpenTelemetry is not available' do
    subject(:interceptor) { described_class.new }

    before do
      allow(described_class).to receive(:otel_available?).and_return(false)
    end

    it '#request_response passes through without span' do
      inter = described_class.new
      result = inter.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(result).to eq(:ok)
    end

    it '#server_streamer passes through without span' do
      inter = described_class.new
      result = inter.server_streamer(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :streamed }
      expect(result).to eq(:streamed)
    end

    it '#client_streamer passes through without span' do
      inter = described_class.new
      result = inter.client_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :client_ok }
      expect(result).to eq(:client_ok)
    end

    it '#bidi_streamer passes through without span' do
      inter = described_class.new
      result = inter.bidi_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :bidi_ok }
      expect(result).to eq(:bidi_ok)
    end
  end

  describe '.otel_available?' do
    it 'returns falsy when OpenTelemetry is not defined' do
      expect(described_class.otel_available?).to be_falsey
    end
  end

  describe 'when OpenTelemetry is available' do
    let(:tracer) { double('tracer') }
    let(:tracer_provider) { double('tracer_provider', tracer: tracer) }

    before do
      allow(described_class).to receive(:otel_available?).and_return(true)
      stub_const('OpenTelemetry', double('OpenTelemetry',
                                         tracer_provider: tracer_provider))
      allow(tracer).to receive(:in_span).and_yield
    end

    it '#request_response wraps call in span' do
      inter = described_class.new
      result = inter.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :traced }
      expect(result).to eq(:traced)
      expect(tracer).to have_received(:in_span).with(
        'kubemq SendEvent', hash_including(kind: :client)
      )
    end

    it '#server_streamer wraps call in span' do
      inter = described_class.new
      result = inter.server_streamer(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :traced_stream }
      expect(result).to eq(:traced_stream)
      expect(tracer).to have_received(:in_span).with(
        'kubemq SendEvent', hash_including(kind: :client)
      )
    end

    it '#client_streamer wraps call in span with producer kind' do
      inter = described_class.new
      result = inter.client_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :traced_client }
      expect(result).to eq(:traced_client)
      expect(tracer).to have_received(:in_span).with(
        'kubemq SendEvent', hash_including(kind: :producer)
      )
    end

    it '#bidi_streamer wraps call in span with producer kind' do
      inter = described_class.new
      result = inter.bidi_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :traced_bidi }
      expect(result).to eq(:traced_bidi)
      expect(tracer).to have_received(:in_span).with(
        'kubemq SendEvent', hash_including(kind: :producer)
      )
    end
  end
end
