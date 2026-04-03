# frozen_string_literal: true

RSpec.describe KubeMQ::Configuration do
  around do |example|
    old_addr = ENV.fetch('KUBEMQ_ADDRESS', nil)
    old_token = ENV.fetch('KUBEMQ_AUTH_TOKEN', nil)
    ENV.delete('KUBEMQ_ADDRESS')
    ENV.delete('KUBEMQ_AUTH_TOKEN')
    KubeMQ.reset_configuration!
    example.run
  ensure
    old_addr ? ENV['KUBEMQ_ADDRESS'] = old_addr : ENV.delete('KUBEMQ_ADDRESS')
    old_token ? ENV['KUBEMQ_AUTH_TOKEN'] = old_token : ENV.delete('KUBEMQ_AUTH_TOKEN')
    KubeMQ.reset_configuration!
  end

  describe '3-layer precedence' do
    it 'constructor args override KubeMQ.configure' do
      KubeMQ.configure { |c| c.address = 'config-host:50000' }
      cfg = described_class.new(address: 'arg-host:50000')
      expect(cfg.address).to eq('arg-host:50000')
    end

    it 'reads KUBEMQ_ADDRESS from ENV' do
      ENV['KUBEMQ_ADDRESS'] = 'env-host:50000'
      cfg = described_class.new
      expect(cfg.address).to eq('env-host:50000')
    end

    it 'reads KUBEMQ_AUTH_TOKEN from ENV' do
      ENV['KUBEMQ_AUTH_TOKEN'] = 'env-token-123'
      cfg = described_class.new
      expect(cfg.auth_token).to eq('env-token-123')
    end

    it 'uses default values when nothing configured' do
      cfg = described_class.new
      expect(cfg.address).to eq('localhost:50000')
      expect(cfg.auth_token).to be_nil
      expect(cfg.client_id).to start_with('kubemq-ruby-')
    end
  end

  describe '#inspect' do
    it 'redacts auth_token when present' do
      cfg = described_class.new(address: 'host:50000', auth_token: 'secret-token')
      expect(cfg.inspect).to include('[REDACTED]')
      expect(cfg.inspect).not_to include('secret-token')
    end

    it 'shows nil when auth_token absent' do
      cfg = described_class.new(address: 'host:50000')
      expect(cfg.inspect).to include('auth_token=nil')
    end
  end

  describe '#validate!' do
    it 'raises ConfigurationError for empty address' do
      cfg = described_class.new(address: '')
      expect { cfg.validate! }.to raise_error(KubeMQ::ConfigurationError, /address is required/)
    end

    it 'raises ConfigurationError for TLS cert without key' do
      tls = KubeMQ::TLSConfig.new(enabled: true, cert_file: '/cert.pem')
      cfg = described_class.new(tls: tls)
      expect { cfg.validate! }
        .to raise_error(KubeMQ::ConfigurationError, /key_file is required/)
    end

    it 'raises ConfigurationError for TLS key without cert' do
      tls = KubeMQ::TLSConfig.new(enabled: true, key_file: '/key.pem')
      cfg = described_class.new(tls: tls)
      expect { cfg.validate! }
        .to raise_error(KubeMQ::ConfigurationError, /cert_file is required/)
    end

    it 'returns true for valid configuration' do
      cfg = described_class.new(address: 'localhost:50000')
      expect(cfg.validate!).to be true
    end
  end

  describe 'defaults' do
    it 'uses sensible defaults for keepalive' do
      cfg = described_class.new
      expect(cfg.keepalive.enabled).to be true
      expect(cfg.keepalive.ping_interval_seconds).to eq(10)
    end

    it 'uses sensible defaults for reconnect_policy' do
      cfg = described_class.new
      expect(cfg.reconnect_policy.enabled).to be true
      expect(cfg.reconnect_policy.base_interval).to eq(1.0)
      expect(cfg.reconnect_policy.max_delay).to eq(30.0)
    end
  end
end
