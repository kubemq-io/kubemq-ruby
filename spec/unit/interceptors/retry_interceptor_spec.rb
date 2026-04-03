# frozen_string_literal: true

RSpec.describe KubeMQ::Interceptors::RetryInterceptor do
  subject(:interceptor) { described_class.new(max_retries: 2, base_delay: 0.001, multiplier: 2.0) }

  let(:request) { double('request') }
  let(:call) { double('call') }
  let(:method) { '/kubemq.Kubemq/SendEvent' }
  let(:metadata) { {} }

  describe '#request_response' do
    it 'passes through on success' do
      result = interceptor.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(result).to eq(:ok)
    end

    it 'retries on UNAVAILABLE and succeeds' do
      attempt = 0
      result = interceptor.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) do |_r, _c, _m, _md|
        attempt += 1
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNAVAILABLE, 'down') if attempt == 1

        :recovered
      end
      expect(result).to eq(:recovered)
      expect(attempt).to eq(2)
    end

    it 'retries on DEADLINE_EXCEEDED' do
      attempt = 0
      result = interceptor.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) do |_r, _c, _m, _md|
        attempt += 1
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::DEADLINE_EXCEEDED, 'timeout') if attempt == 1

        :ok
      end
      expect(result).to eq(:ok)
      expect(attempt).to eq(2)
    end

    it 'retries on ABORTED' do
      attempt = 0
      result = interceptor.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) do |_r, _c, _m, _md|
        attempt += 1
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::ABORTED, 'aborted') if attempt == 1

        :ok
      end
      expect(result).to eq(:ok)
    end

    it 'does not retry non-retryable codes' do
      attempt = 0
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) do |_r, _c, _m, _md|
          attempt += 1
          raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::INVALID_ARGUMENT, 'bad arg')
        end
      end.to raise_error(GRPC::BadStatus)
      expect(attempt).to eq(1)
    end

    it 'exhausts retries and raises the last error' do
      attempt = 0
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) do |_r, _c, _m, _md|
          attempt += 1
          raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNAVAILABLE, "fail #{attempt}")
        end
      end.to raise_error(GRPC::BadStatus, /fail 3/)
      expect(attempt).to eq(3)
    end
  end

  describe '#server_streamer' do
    it 'does not retry (pass-through)' do
      result = interceptor.server_streamer(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :streamed }
      expect(result).to eq(:streamed)
    end
  end

  describe '#client_streamer' do
    it 'does not retry (pass-through)' do
      result = interceptor.client_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :client_ok }
      expect(result).to eq(:client_ok)
    end
  end

  describe '#bidi_streamer' do
    it 'does not retry (pass-through)' do
      result = interceptor.bidi_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :bidi_ok }
      expect(result).to eq(:bidi_ok)
    end
  end

  describe 'default parameters' do
    it 'uses default values when none provided' do
      default_interceptor = described_class.new
      expect(default_interceptor).to be_a(described_class)
    end
  end
end
