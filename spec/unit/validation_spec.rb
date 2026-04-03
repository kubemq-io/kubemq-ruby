# frozen_string_literal: true

RSpec.describe KubeMQ::Validator do
  describe '.validate_channel!' do
    it 'raises ValidationError when channel is empty' do
      expect { described_class.validate_channel!('') }
        .to raise_error(KubeMQ::ValidationError, /Channel name is required/)
    end

    it 'raises ValidationError when channel is nil' do
      expect { described_class.validate_channel!(nil) }
        .to raise_error(KubeMQ::ValidationError, /Channel name is required/)
    end

    it 'raises ValidationError when channel contains whitespace only' do
      expect { described_class.validate_channel!('   ') }
        .to raise_error(KubeMQ::ValidationError, /Channel name is required/)
    end

    it 'raises ValidationError when channel ends with dot' do
      expect { described_class.validate_channel!('test.') }
        .to raise_error(KubeMQ::ValidationError, /must not end with a dot/)
    end

    it 'allows wildcard * for Events subscribe' do
      expect { described_class.validate_channel!('test.*', allow_wildcards: true) }
        .not_to raise_error
    end

    it 'allows wildcard > for Events subscribe' do
      expect { described_class.validate_channel!('test.>', allow_wildcards: true) }
        .not_to raise_error
    end

    it 'rejects wildcard * when wildcards not allowed' do
      expect { described_class.validate_channel!('test.*', allow_wildcards: false) }
        .to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'rejects wildcard > when wildcards not allowed' do
      expect { described_class.validate_channel!('test.>', allow_wildcards: false) }
        .to raise_error(KubeMQ::ValidationError, /Wildcards are not allowed/)
    end

    it 'rejects channel with invalid characters' do
      expect { described_class.validate_channel!('test channel!') }
        .to raise_error(KubeMQ::ValidationError, /invalid characters/)
    end

    it 'accepts valid channel names' do
      expect { described_class.validate_channel!('my-channel') }.not_to raise_error
      expect { described_class.validate_channel!('my.channel') }.not_to raise_error
      expect { described_class.validate_channel!('my_channel') }.not_to raise_error
      expect { described_class.validate_channel!('my/channel') }.not_to raise_error
    end
  end

  describe '.validate_content!' do
    it 'raises ValidationError when metadata and body are both empty' do
      expect { described_class.validate_content!('', '') }
        .to raise_error(KubeMQ::ValidationError, /must have non-empty metadata or body/)
    end

    it 'raises ValidationError when metadata and body are both nil' do
      expect { described_class.validate_content!(nil, nil) }
        .to raise_error(KubeMQ::ValidationError, /must have non-empty metadata or body/)
    end

    it 'allows metadata only' do
      expect { described_class.validate_content!('meta', nil) }.not_to raise_error
    end

    it 'allows body only' do
      expect { described_class.validate_content!(nil, 'body') }.not_to raise_error
    end
  end

  describe '.validate_client_id!' do
    it 'raises ValidationError when client_id is empty' do
      expect { described_class.validate_client_id!('') }
        .to raise_error(KubeMQ::ValidationError, /Client ID is required/)
    end

    it 'raises ValidationError when client_id is nil' do
      expect { described_class.validate_client_id!(nil) }
        .to raise_error(KubeMQ::ValidationError, /Client ID is required/)
    end
  end

  describe '.validate_timeout!' do
    it 'raises ValidationError when command timeout is 0' do
      expect { described_class.validate_timeout!(0) }
        .to raise_error(KubeMQ::ValidationError, /Timeout must be greater than 0/)
    end

    it 'raises ValidationError when command timeout is negative' do
      expect { described_class.validate_timeout!(-1) }
        .to raise_error(KubeMQ::ValidationError, /Timeout must be greater than 0/)
    end

    it 'accepts positive timeout' do
      expect { described_class.validate_timeout!(1000) }.not_to raise_error
    end
  end

  describe '.validate_cache!' do
    it 'raises ValidationError when cache_key set but cache_ttl is 0' do
      expect { described_class.validate_cache!('key', 0) }
        .to raise_error(KubeMQ::ValidationError, /cache_ttl must be > 0/)
    end

    it 'raises ValidationError when cache_key set but cache_ttl is nil' do
      expect { described_class.validate_cache!('key', nil) }
        .to raise_error(KubeMQ::ValidationError, /cache_ttl must be > 0/)
    end

    it 'accepts valid cache_key with positive cache_ttl' do
      expect { described_class.validate_cache!('key', 60) }.not_to raise_error
    end

    it 'skips validation when cache_key is nil' do
      expect { described_class.validate_cache!(nil, 0) }.not_to raise_error
    end
  end

  describe '.validate_response!' do
    it 'raises ValidationError when request_id is empty on SendResponse' do
      expect { described_class.validate_response!('', 'reply') }
        .to raise_error(KubeMQ::ValidationError, /request_id is required/)
    end

    it 'raises ValidationError when reply_channel is empty on SendResponse' do
      expect { described_class.validate_response!('req-1', '') }
        .to raise_error(KubeMQ::ValidationError, /reply_channel is required/)
    end

    it 'accepts valid response parameters' do
      expect { described_class.validate_response!('req-1', 'reply-ch') }.not_to raise_error
    end
  end

  describe '.validate_events_store_subscription!' do
    it 'raises ValidationError when events_store start_position is Undefined (0)' do
      expect { described_class.validate_events_store_subscription!(0, 0) }
        .to raise_error(KubeMQ::ValidationError, /requires a start position/)
    end

    it 'raises ValidationError when start_at_sequence value is 0' do
      expect { described_class.validate_events_store_subscription!(4, 0) }
        .to raise_error(KubeMQ::ValidationError, /StartAtSequence requires a positive/)
    end

    it 'raises ValidationError when start_at_time value is 0' do
      expect { described_class.validate_events_store_subscription!(5, 0) }
        .to raise_error(KubeMQ::ValidationError, /StartAtTime requires a positive/)
    end

    it 'raises ValidationError when start_at_time_delta value is 0' do
      expect { described_class.validate_events_store_subscription!(6, 0) }
        .to raise_error(KubeMQ::ValidationError, /StartAtTimeDelta requires a positive/)
    end

    it 'accepts valid StartNewOnly' do
      expect { described_class.validate_events_store_subscription!(1, 0) }.not_to raise_error
    end

    it 'accepts valid StartAtSequence with positive value' do
      expect { described_class.validate_events_store_subscription!(4, 10) }.not_to raise_error
    end
  end

  describe '.validate_queue_poll!' do
    it 'raises ValidationError for max_items < 1' do
      expect { described_class.validate_queue_poll!(0, 1) }
        .to raise_error(KubeMQ::ValidationError, /max_items must be >= 1/)
    end

    it 'raises ValidationError for wait_timeout > 3600' do
      expect { described_class.validate_queue_poll!(1, 3601) }
        .to raise_error(KubeMQ::ValidationError, /wait_timeout must be between 0 and 3600/)
    end

    it 'accepts valid poll parameters' do
      expect { described_class.validate_queue_poll!(10, 30) }.not_to raise_error
    end
  end

  describe '.validate_queue_receive!' do
    it 'raises ValidationError for max_messages > 1024' do
      expect { described_class.validate_queue_receive!(1025, 1) }
        .to raise_error(KubeMQ::ValidationError, /max_messages must be between 1 and 1024/)
    end

    it 'raises ValidationError for wait_timeout_seconds > 3600' do
      expect { described_class.validate_queue_receive!(1, 3601) }
        .to raise_error(KubeMQ::ValidationError, /wait_timeout_seconds must be between 0 and 3600/)
    end

    it 'accepts valid receive parameters' do
      expect { described_class.validate_queue_receive!(100, 30) }.not_to raise_error
    end
  end
end
