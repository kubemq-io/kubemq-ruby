# frozen_string_literal: true

RSpec.describe KubeMQ::Interceptors::ErrorMappingInterceptor do
  subject(:interceptor) { described_class.new }

  let(:request) { double('request') }
  let(:call) { double('call') }
  let(:method) { '/kubemq.Kubemq/SendEvent' }
  let(:metadata) { {} }

  describe '#request_response' do
    it 'yields through on success' do
      result = interceptor.request_response(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :ok }
      expect(result).to eq(:ok)
    end

    {
      GRPC::Core::StatusCodes::CANCELLED =>
        [KubeMQ::CancellationError, KubeMQ::ErrorCode::CANCELLED, false],
      GRPC::Core::StatusCodes::UNKNOWN =>
        [KubeMQ::Error, KubeMQ::ErrorCode::UNKNOWN, true],
      GRPC::Core::StatusCodes::INVALID_ARGUMENT =>
        [KubeMQ::ValidationError, KubeMQ::ErrorCode::VALIDATION_ERROR, false],
      GRPC::Core::StatusCodes::DEADLINE_EXCEEDED =>
        [KubeMQ::TimeoutError, KubeMQ::ErrorCode::CONNECTION_TIMEOUT, true],
      GRPC::Core::StatusCodes::NOT_FOUND =>
        [KubeMQ::ChannelError, KubeMQ::ErrorCode::NOT_FOUND, false],
      GRPC::Core::StatusCodes::ALREADY_EXISTS =>
        [KubeMQ::ValidationError, KubeMQ::ErrorCode::ALREADY_EXISTS, false],
      GRPC::Core::StatusCodes::PERMISSION_DENIED =>
        [KubeMQ::AuthenticationError, KubeMQ::ErrorCode::PERMISSION_DENIED, false],
      GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED =>
        [KubeMQ::MessageError, KubeMQ::ErrorCode::RESOURCE_EXHAUSTED, true],
      GRPC::Core::StatusCodes::FAILED_PRECONDITION =>
        [KubeMQ::ValidationError, KubeMQ::ErrorCode::VALIDATION_ERROR, false],
      GRPC::Core::StatusCodes::ABORTED =>
        [KubeMQ::TransactionError, KubeMQ::ErrorCode::ABORTED, true],
      GRPC::Core::StatusCodes::OUT_OF_RANGE =>
        [KubeMQ::ValidationError, KubeMQ::ErrorCode::OUT_OF_RANGE, false],
      GRPC::Core::StatusCodes::UNIMPLEMENTED =>
        [KubeMQ::Error, KubeMQ::ErrorCode::UNIMPLEMENTED, false],
      GRPC::Core::StatusCodes::INTERNAL =>
        [KubeMQ::Error, KubeMQ::ErrorCode::INTERNAL, false],
      GRPC::Core::StatusCodes::UNAVAILABLE =>
        [KubeMQ::ConnectionError, KubeMQ::ErrorCode::UNAVAILABLE, true],
      GRPC::Core::StatusCodes::DATA_LOSS =>
        [KubeMQ::Error, KubeMQ::ErrorCode::DATA_LOSS, false],
      GRPC::Core::StatusCodes::UNAUTHENTICATED =>
        [KubeMQ::AuthenticationError, KubeMQ::ErrorCode::AUTH_FAILED, false]
    }.each do |grpc_code, (expected_class, expected_code, expected_retryable)|
      it "maps gRPC code #{grpc_code} to #{expected_class}" do
        grpc_error = GRPC::BadStatus.new(grpc_code, "error for code #{grpc_code}")
        err = nil
        begin
          interceptor.request_response(
            request: request, call: call, method: method, metadata: metadata
          ) { |_r, _c, _m, _md| raise grpc_error }
        rescue StandardError => e
          err = e
        end
        expect(err).to be_a(expected_class)
        expect(err.code).to eq(expected_code)
        expect(err.retryable?).to eq(expected_retryable) if err.respond_to?(:retryable?)
      end
    end

    it 'maps unknown gRPC code to KubeMQ::Error with UNKNOWN code' do
      grpc_error = GRPC::BadStatus.new(99, 'unknown status')
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::Error) { |err|
        expect(err.code).to eq(KubeMQ::ErrorCode::UNKNOWN)
        expect(err.cause).to eq(grpc_error)
      }
    end
  end

  describe '#server_streamer' do
    it 'yields through on success' do
      result = interceptor.server_streamer(
        request: request, call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :streamed }
      expect(result).to eq(:streamed)
    end

    it 'maps gRPC errors' do
      grpc_error = GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNAVAILABLE, 'down')
      expect do
        interceptor.server_streamer(
          request: request, call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::ConnectionError)
    end
  end

  describe '#client_streamer' do
    it 'yields through on success' do
      result = interceptor.client_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :client_stream_ok }
      expect(result).to eq(:client_stream_ok)
    end

    it 'maps gRPC errors' do
      grpc_error = GRPC::BadStatus.new(GRPC::Core::StatusCodes::INTERNAL, 'server err')
      expect do
        interceptor.client_streamer(
          requests: [request], call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::Error) { |err|
        expect(err.code).to eq(KubeMQ::ErrorCode::INTERNAL)
      }
    end
  end

  describe '#bidi_streamer' do
    it 'yields through on success' do
      result = interceptor.bidi_streamer(
        requests: [request], call: call, method: method, metadata: metadata
      ) { |_r, _c, _m, _md| :bidi_ok }
      expect(result).to eq(:bidi_ok)
    end

    it 'maps gRPC errors' do
      grpc_error = GRPC::BadStatus.new(GRPC::Core::StatusCodes::PERMISSION_DENIED, 'denied')
      expect do
        interceptor.bidi_streamer(
          requests: [request], call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::AuthenticationError)
    end
  end

  describe 'credential scrubbing' do
    it 'scrubs bearer tokens from error details' do
      grpc_error = GRPC::BadStatus.new(
        GRPC::Core::StatusCodes::UNAUTHENTICATED,
        'authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.abc123'
      )
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::AuthenticationError) { |err|
        expect(err.message).not_to include('eyJ')
        expect(err.message).to include('[REDACTED]')
      }
    end

    it 'scrubs JWT tokens from error details' do
      grpc_error = GRPC::BadStatus.new(
        GRPC::Core::StatusCodes::UNKNOWN,
        'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.signature invalid'
      )
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::Error) { |err|
        expect(err.message).not_to include('eyJhbGci')
      }
    end

    it 'handles nil error details' do
      grpc_error = GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNKNOWN, nil)
      expect do
        interceptor.request_response(
          request: request, call: call, method: method, metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      end.to raise_error(KubeMQ::Error)
    end
  end

  describe 'operation extraction' do
    it 'extracts operation name from method path' do
      grpc_error = GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNKNOWN, 'err')
      begin
        interceptor.request_response(
          request: request, call: call, method: '/kubemq.Kubemq/SendEvent', metadata: metadata
        ) { |_r, _c, _m, _md| raise grpc_error }
      rescue KubeMQ::Error => e
        expect(e.operation).to eq('SendEvent')
      end
    end
  end
end
