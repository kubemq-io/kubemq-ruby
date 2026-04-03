# frozen_string_literal: true

RSpec.describe KubeMQ::Error do
  describe 'error hierarchy' do
    it 'inherits from StandardError' do
      expect(KubeMQ::Error.ancestors).to include(StandardError)
    end

    it 'ConnectionError inherits from Error' do
      expect(KubeMQ::ConnectionError.ancestors).to include(KubeMQ::Error)
    end

    it 'AuthenticationError inherits from ConnectionError' do
      expect(KubeMQ::AuthenticationError.ancestors).to include(KubeMQ::ConnectionError)
    end

    it 'TimeoutError inherits from Error' do
      expect(KubeMQ::TimeoutError.ancestors).to include(KubeMQ::Error)
    end

    it 'ValidationError inherits from Error' do
      expect(KubeMQ::ValidationError.ancestors).to include(KubeMQ::Error)
    end

    it 'ConfigurationError inherits from Error' do
      expect(KubeMQ::ConfigurationError.ancestors).to include(KubeMQ::Error)
    end

    it 'ChannelError inherits from Error' do
      expect(KubeMQ::ChannelError.ancestors).to include(KubeMQ::Error)
    end

    it 'MessageError inherits from Error' do
      expect(KubeMQ::MessageError.ancestors).to include(KubeMQ::Error)
    end

    it 'TransactionError inherits from Error' do
      expect(KubeMQ::TransactionError.ancestors).to include(KubeMQ::Error)
    end

    it 'ClientClosedError inherits from Error' do
      expect(KubeMQ::ClientClosedError.ancestors).to include(KubeMQ::Error)
    end

    it 'ConnectionNotReadyError inherits from Error' do
      expect(KubeMQ::ConnectionNotReadyError.ancestors).to include(KubeMQ::Error)
    end

    it 'StreamBrokenError inherits from Error' do
      expect(KubeMQ::StreamBrokenError.ancestors).to include(KubeMQ::Error)
    end

    it 'BufferFullError inherits from Error' do
      expect(KubeMQ::BufferFullError.ancestors).to include(KubeMQ::Error)
    end

    it 'CancellationError inherits from Error' do
      expect(KubeMQ::CancellationError.ancestors).to include(KubeMQ::Error)
    end
  end

  describe 'error attributes' do
    let(:error) do
      KubeMQ::Error.new(
        'test error',
        code: 'TEST_CODE',
        details: { key: 'val' },
        operation: 'send_event',
        channel: 'test-ch',
        request_id: 'req-1',
        suggestion: 'Try again.',
        retryable: true
      )
    end

    it 'stores code' do
      expect(error.code).to eq('TEST_CODE')
    end

    it 'stores details hash' do
      expect(error.details).to eq({ key: 'val' })
    end

    it 'stores operation' do
      expect(error.operation).to eq('send_event')
    end

    it 'stores channel' do
      expect(error.channel).to eq('test-ch')
    end

    it 'stores request_id' do
      expect(error.request_id).to eq('req-1')
    end

    it 'stores suggestion' do
      expect(error.suggestion).to eq('Try again.')
    end

    it 'reports retryable?' do
      expect(error).to be_retryable
    end

    it 'defaults retryable to false' do
      err = KubeMQ::Error.new('msg')
      expect(err).not_to be_retryable
    end

    it 'defaults details to empty hash' do
      err = KubeMQ::Error.new('msg')
      expect(err.details).to eq({})
    end
  end

  describe '#to_s' do
    it 'includes operation and channel when both present' do
      err = KubeMQ::Error.new('boom', operation: 'send_event', channel: 'ch1')
      expect(err.to_s).to include('send_event failed on channel')
      expect(err.to_s).to include('ch1')
    end

    it 'includes operation without channel' do
      err = KubeMQ::Error.new('boom', operation: 'connect')
      expect(err.to_s).to include('connect failed: boom')
    end

    it 'includes suggestion when present' do
      err = KubeMQ::Error.new('boom', suggestion: 'Check logs.')
      expect(err.to_s).to include('Suggestion: Check logs.')
    end
  end

  describe 'subclass defaults' do
    it 'TimeoutError defaults to retryable' do
      err = KubeMQ::TimeoutError.new('timed out')
      expect(err).to be_retryable
      expect(err.code).to eq(KubeMQ::ErrorCode::CONNECTION_TIMEOUT)
    end

    it 'ValidationError defaults to non-retryable' do
      err = KubeMQ::ValidationError.new('invalid')
      expect(err).not_to be_retryable
    end

    it 'AuthenticationError defaults to non-retryable' do
      err = KubeMQ::AuthenticationError.new('auth failed')
      expect(err).not_to be_retryable
    end

    it 'ConfigurationError sets code and non-retryable' do
      err = KubeMQ::ConfigurationError.new('bad config')
      expect(err.code).to eq(KubeMQ::ErrorCode::CONFIGURATION_ERROR)
      expect(err).not_to be_retryable
    end

    it 'ClientClosedError has default message' do
      err = KubeMQ::ClientClosedError.new
      expect(err.message).to eq('Client is closed')
      expect(err.code).to eq(KubeMQ::ErrorCode::CLIENT_CLOSED)
    end

    it 'ConnectionNotReadyError has default message' do
      err = KubeMQ::ConnectionNotReadyError.new
      expect(err.message).to eq('Connection is not ready')
    end

    it 'StreamBrokenError stores unacked_message_ids' do
      err = KubeMQ::StreamBrokenError.new('broken', unacked_message_ids: %w[a b])
      expect(err.unacked_message_ids).to eq(%w[a b])
      expect(err).to be_retryable
    end

    it 'BufferFullError stores buffer_size' do
      err = KubeMQ::BufferFullError.new('full', buffer_size: 1000)
      expect(err.buffer_size).to eq(1000)
      expect(err.code).to eq(KubeMQ::ErrorCode::BUFFER_FULL)
    end

    it 'CancellationError has default message' do
      err = KubeMQ::CancellationError.new
      expect(err.message).to eq('Operation cancelled')
      expect(err.code).to eq(KubeMQ::ErrorCode::CANCELLED)
    end
  end

  describe 'KubeMQ.classify_error' do
    it 'returns FATAL for errors without a code method' do
      err = StandardError.new('plain error')
      category, retryable = KubeMQ.classify_error(err)
      expect(category).to eq(KubeMQ::ErrorCategory::FATAL)
      expect(retryable).to be false
    end

    it 'classifies known error codes' do
      err = KubeMQ::Error.new('unavailable', code: KubeMQ::ErrorCode::UNAVAILABLE)
      category, retryable = KubeMQ.classify_error(err)
      expect(category).to eq(KubeMQ::ErrorCategory::TRANSIENT)
      expect(retryable).to be true
    end

    it 'returns FATAL for unknown error codes' do
      err = KubeMQ::Error.new('weird', code: 'TOTALLY_UNKNOWN_CODE')
      category, retryable = KubeMQ.classify_error(err)
      expect(category).to eq(KubeMQ::ErrorCategory::FATAL)
      expect(retryable).to be false
    end
  end

  describe 'gRPC error mapping' do
    let(:interceptor) { KubeMQ::Interceptors::ErrorMappingInterceptor.new }
    let(:grpc_mapping) { KubeMQ::Interceptors::ErrorMappingInterceptor::GRPC_MAPPING }

    {
      GRPC::Core::StatusCodes::CANCELLED => [KubeMQ::CancellationError, KubeMQ::ErrorCode::CANCELLED, false],
      GRPC::Core::StatusCodes::UNKNOWN => [KubeMQ::Error, KubeMQ::ErrorCode::UNKNOWN, true],
      GRPC::Core::StatusCodes::INVALID_ARGUMENT => [KubeMQ::ValidationError, KubeMQ::ErrorCode::VALIDATION_ERROR,
                                                    false],
      GRPC::Core::StatusCodes::DEADLINE_EXCEEDED => [KubeMQ::TimeoutError, KubeMQ::ErrorCode::CONNECTION_TIMEOUT, true],
      GRPC::Core::StatusCodes::NOT_FOUND => [KubeMQ::ChannelError, KubeMQ::ErrorCode::NOT_FOUND, false],
      GRPC::Core::StatusCodes::ALREADY_EXISTS => [KubeMQ::ValidationError, KubeMQ::ErrorCode::ALREADY_EXISTS, false],
      GRPC::Core::StatusCodes::PERMISSION_DENIED => [KubeMQ::AuthenticationError, KubeMQ::ErrorCode::PERMISSION_DENIED,
                                                     false],
      GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED => [KubeMQ::MessageError, KubeMQ::ErrorCode::RESOURCE_EXHAUSTED,
                                                      true],
      GRPC::Core::StatusCodes::FAILED_PRECONDITION => [KubeMQ::ValidationError, KubeMQ::ErrorCode::VALIDATION_ERROR,
                                                       false],
      GRPC::Core::StatusCodes::ABORTED => [KubeMQ::TransactionError, KubeMQ::ErrorCode::ABORTED, true],
      GRPC::Core::StatusCodes::OUT_OF_RANGE => [KubeMQ::ValidationError, KubeMQ::ErrorCode::OUT_OF_RANGE, false],
      GRPC::Core::StatusCodes::UNIMPLEMENTED => [KubeMQ::Error, KubeMQ::ErrorCode::UNIMPLEMENTED, false],
      GRPC::Core::StatusCodes::INTERNAL => [KubeMQ::Error, KubeMQ::ErrorCode::INTERNAL, false],
      GRPC::Core::StatusCodes::UNAVAILABLE => [KubeMQ::ConnectionError, KubeMQ::ErrorCode::UNAVAILABLE, true],
      GRPC::Core::StatusCodes::DATA_LOSS => [KubeMQ::Error, KubeMQ::ErrorCode::DATA_LOSS, false],
      GRPC::Core::StatusCodes::UNAUTHENTICATED => [KubeMQ::AuthenticationError, KubeMQ::ErrorCode::AUTH_FAILED, false]
    }.each do |grpc_code, (expected_class, expected_code, expected_retryable)|
      it "maps gRPC #{grpc_code} to #{expected_class}" do
        mapping = grpc_mapping[grpc_code]
        expect(mapping).not_to be_nil
        exc_class, code, retryable = mapping
        expect(exc_class).to eq(expected_class)
        expect(code).to eq(expected_code)
        expect(retryable).to eq(expected_retryable)
      end
    end
  end
end
