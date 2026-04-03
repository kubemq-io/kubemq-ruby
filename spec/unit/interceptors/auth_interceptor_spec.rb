# frozen_string_literal: true

RSpec.describe KubeMQ::Interceptors::AuthInterceptor do
  let(:request) { double('request') }
  let(:call) { double('call') }
  let(:metadata) { {} }

  describe '#request_response' do
    it 'injects authorization header' do
      interceptor = described_class.new('my-token')
      interceptor.request_response(
        request: request, call: call, method: '/kubemq.Kubemq/SendEvent', metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(metadata['authorization']).to eq('my-token')
    end

    it 'skips injection for nil token' do
      interceptor = described_class.new(nil)
      interceptor.request_response(
        request: request, call: call, method: '/kubemq.Kubemq/SendEvent', metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(metadata).not_to have_key('authorization')
    end

    it 'skips injection for empty token' do
      interceptor = described_class.new('')
      interceptor.request_response(
        request: request, call: call, method: '/kubemq.Kubemq/SendEvent', metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(metadata).not_to have_key('authorization')
    end

    it 'skips injection for Ping method' do
      interceptor = described_class.new('my-token')
      interceptor.request_response(
        request: request, call: call, method: '/kubemq.Kubemq/Ping', metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(metadata).not_to have_key('authorization')
    end
  end

  describe '#server_streamer' do
    it 'injects auth for non-Ping methods' do
      interceptor = described_class.new('token-2')
      md = {}
      interceptor.server_streamer(
        request: request, call: call, method: '/kubemq.Kubemq/Subscribe', metadata: md
      ) { |_r, _c, _m, _md| :ok }
      expect(md['authorization']).to eq('token-2')
    end
  end

  describe '#client_streamer' do
    it 'injects auth for non-Ping methods' do
      interceptor = described_class.new('token-3')
      md = {}
      interceptor.client_streamer(
        requests: [request], call: call, method: '/kubemq.Kubemq/Stream', metadata: md
      ) { |_r, _c, _m, _md| :ok }
      expect(md['authorization']).to eq('token-3')
    end
  end

  describe '#bidi_streamer' do
    it 'injects auth for non-Ping methods' do
      interceptor = described_class.new('token-4')
      md = {}
      interceptor.bidi_streamer(
        requests: [request], call: call, method: '/kubemq.Kubemq/BiDi', metadata: md
      ) { |_r, _c, _m, _md| :ok }
      expect(md['authorization']).to eq('token-4')
    end

    it 'skips injection for Ping method' do
      interceptor = described_class.new('token-4')
      md = {}
      interceptor.bidi_streamer(
        requests: [request], call: call, method: '/kubemq.Kubemq/Ping', metadata: md
      ) { |_r, _c, _m, _md| :ok }
      expect(md).not_to have_key('authorization')
    end
  end
end
