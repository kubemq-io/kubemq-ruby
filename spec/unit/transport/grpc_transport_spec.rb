# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::GrpcTransport do
  let(:config) { KubeMQ::Configuration.new(address: 'localhost:50000') }
  subject(:transport) { described_class.new(config) }

  describe '#initialize' do
    it 'creates a state machine in IDLE state' do
      expect(transport.state_machine.current_state).to eq(KubeMQ::ConnectionState::IDLE)
    end

    it 'creates an empty message buffer' do
      expect(transport.buffer).to be_empty
    end

    it 'is not closed initially' do
      expect(transport).not_to be_closed
    end
  end

  describe '#close' do
    it 'marks transport as closed' do
      allow(transport).to receive(:cancel_subscriptions)
      allow(transport).to receive(:flush_buffer)
      transport.close
      expect(transport).to be_closed
    end

    it 'is idempotent' do
      allow(transport).to receive(:cancel_subscriptions)
      allow(transport).to receive(:flush_buffer)
      transport.close
      expect { transport.close }.not_to raise_error
    end

    it 'transitions state machine to CLOSED' do
      allow(transport).to receive(:cancel_subscriptions)
      allow(transport).to receive(:flush_buffer)
      transport.close
      expect(transport.state_machine).to be_closed
    end
  end

  describe '#ensure_connected!' do
    it 'raises ClientClosedError when already closed' do
      allow(transport).to receive(:cancel_subscriptions)
      allow(transport).to receive(:flush_buffer)
      transport.close
      expect { transport.ensure_connected! }.to raise_error(KubeMQ::ClientClosedError)
    end

    it 'raises ConnectionError when connect fails' do
      allow(GRPC::Core::Channel).to receive(:new).and_raise(StandardError, 'connection refused')

      expect { transport.ensure_connected! }.to raise_error(KubeMQ::ConnectionError)
    end
  end

  describe '#register_subscription / #unregister_subscription' do
    it 'tracks subscription threads' do
      thread = Thread.new { sleep(0.1) }
      transport.register_subscription(thread)
      transport.unregister_subscription(thread)
      thread.join
    end
  end

  describe '#kubemq_client' do
    it 'calls ensure_connected! before returning stub' do
      expect(transport).to receive(:ensure_connected!)
      allow(transport).to receive(:instance_variable_get).with(:@stub).and_return(double('stub'))
      transport.kubemq_client
    end
  end

  describe 'state_machine accessor' do
    it 'exposes state_machine' do
      expect(transport.state_machine).to be_a(KubeMQ::Transport::ConnectionStateMachine)
    end
  end

  describe 'buffer accessor' do
    it 'exposes message buffer' do
      expect(transport.buffer).to be_a(KubeMQ::Transport::MessageBuffer)
    end
  end

  describe 'keepalive options' do
    it 'includes keepalive when enabled' do
      cfg = KubeMQ::Configuration.new(
        address: 'host:50000',
        keepalive: KubeMQ::KeepAliveConfig.new(
          enabled: true,
          ping_interval_seconds: 20,
          ping_timeout_seconds: 10
        )
      )
      t = described_class.new(cfg)
      opts = t.send(:channel_options)
      expect(opts['grpc.keepalive_time_ms']).to eq(20_000)
      expect(opts['grpc.keepalive_timeout_ms']).to eq(10_000)
    end

    it 'omits keepalive options when disabled' do
      cfg = KubeMQ::Configuration.new(
        address: 'host:50000',
        keepalive: KubeMQ::KeepAliveConfig.new(enabled: false)
      )
      t = described_class.new(cfg)
      opts = t.send(:channel_options)
      expect(opts).not_to have_key('grpc.keepalive_time_ms')
    end
  end

  describe 'TLS credentials' do
    it 'returns insecure channel for non-TLS' do
      t = described_class.new(config)
      creds = t.send(:create_channel_credentials)
      expect(creds).to eq(:this_channel_is_insecure)
    end

    it 'creates basic TLS credentials when tls enabled with no files' do
      tls_cfg = KubeMQ::TLSConfig.new(enabled: true)
      cfg = KubeMQ::Configuration.new(address: 'host:50000', tls: tls_cfg)
      t = described_class.new(cfg)
      expect(GRPC::Core::ChannelCredentials).to receive(:new).with(no_args).and_return(:tls_creds)
      creds = t.send(:create_channel_credentials)
      expect(creds).to eq(:tls_creds)
    end

    it 'creates CA-only TLS credentials when ca_file provided' do
      tls_cfg = KubeMQ::TLSConfig.new(enabled: true, ca_file: '/tmp/ca.pem')
      cfg = KubeMQ::Configuration.new(address: 'host:50000', tls: tls_cfg)
      t = described_class.new(cfg)
      allow(File).to receive(:read).with('/tmp/ca.pem').and_return('ca-data')
      expect(GRPC::Core::ChannelCredentials).to receive(:new).with('ca-data').and_return(:ca_creds)
      creds = t.send(:create_channel_credentials)
      expect(creds).to eq(:ca_creds)
    end

    it 'creates mutual TLS credentials when cert and key files provided' do
      tls_cfg = KubeMQ::TLSConfig.new(
        enabled: true, cert_file: '/tmp/cert.pem',
        key_file: '/tmp/key.pem', ca_file: '/tmp/ca.pem'
      )
      cfg = KubeMQ::Configuration.new(address: 'host:50000', tls: tls_cfg)
      t = described_class.new(cfg)
      allow(File).to receive(:read).with('/tmp/ca.pem').and_return('ca-data')
      allow(File).to receive(:read).with('/tmp/key.pem').and_return('key-data')
      allow(File).to receive(:read).with('/tmp/cert.pem').and_return('cert-data')
      expect(GRPC::Core::ChannelCredentials).to receive(:new)
        .with('ca-data', 'key-data', 'cert-data').and_return(:mtls_creds)
      creds = t.send(:create_channel_credentials)
      expect(creds).to eq(:mtls_creds)
    end
  end

  describe '#recreate_channel!' do
    it 'recreates channel and stub' do
      allow(GRPC::Core::Channel).to receive(:new).and_raise(StandardError, 'cannot connect')
      expect { transport.recreate_channel! }.to raise_error(KubeMQ::ConnectionError)
    end
  end

  describe '#ping' do
    it 'calls stub.ping and returns ServerInfo' do
      ping_result = double('PingResult',
                           Host: 'localhost',
                           Version: '1.0',
                           ServerStartTime: 100,
                           ServerUpTimeSeconds: 500)
      stub = double('stub')
      allow(stub).to receive(:ping).and_return(ping_result)
      transport.instance_variable_set(:@stub, stub)
      result = transport.ping
      expect(result).to be_a(KubeMQ::ServerInfo)
      expect(result.host).to eq('localhost')
    end
  end

  describe 'interceptors' do
    it 'creates interceptor chain with 4 interceptors' do
      interceptors = transport.send(:create_interceptors)
      expect(interceptors.size).to eq(4)
      expect(interceptors[0]).to be_a(KubeMQ::Interceptors::AuthInterceptor)
      expect(interceptors[3]).to be_a(KubeMQ::Interceptors::ErrorMappingInterceptor)
    end
  end

  describe '#cancel_subscriptions' do
    it 'handles no subscriptions gracefully' do
      expect { transport.send(:cancel_subscriptions) }.not_to raise_error
    end

    it 'handles dead threads in subscription list' do
      thread = Thread.new { nil }
      thread.join
      transport.register_subscription(thread)
      expect { transport.send(:cancel_subscriptions) }.not_to raise_error
    end
  end

  describe '#flush_buffer' do
    it 'drains empty buffer without error' do
      expect { transport.send(:flush_buffer, timeout: 1) }.not_to raise_error
    end
  end

  describe 'connect! failure path' do
    it 'transitions to IDLE on connect failure then raises ConnectionError' do
      allow(GRPC::Core::Channel).to receive(:new).and_raise(StandardError, 'refused')
      expect { transport.send(:connect!) }.to raise_error(KubeMQ::ConnectionError, /refused/)
      expect(transport.state_machine.current_state).to eq(KubeMQ::ConnectionState::IDLE)
    end
  end
end
