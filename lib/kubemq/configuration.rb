# frozen_string_literal: true

module KubeMQ
  # TLS/SSL configuration for secure broker connections.
  #
  # Enable mutual TLS (mTLS) by providing both +cert_file+ and +key_file+.
  # For server-only TLS, set +ca_file+ alone or use +insecure_skip_verify+
  # for self-signed certificates in development.
  #
  # @example mTLS configuration
  #   tls = KubeMQ::TLSConfig.new(
  #     enabled: true,
  #     cert_file: "/certs/client.pem",
  #     key_file: "/certs/client-key.pem",
  #     ca_file: "/certs/ca.pem"
  #   )
  #
  # @see Configuration
  class TLSConfig
    # @!attribute [rw] enabled
    #   @return [Boolean] whether TLS is enabled (default: +false+)
    # @!attribute [rw] cert_file
    #   @return [String, nil] path to client certificate PEM file
    # @!attribute [rw] key_file
    #   @return [String, nil] path to client private key PEM file
    # @!attribute [rw] ca_file
    #   @return [String, nil] path to CA certificate PEM file
    # @!attribute [rw] insecure_skip_verify
    #   @return [Boolean] skip server certificate verification (default: +false+)
    attr_accessor :enabled, :cert_file, :key_file, :ca_file, :insecure_skip_verify

    # Creates a new TLS configuration.
    #
    # @param enabled [Boolean] whether TLS is enabled (default: +false+)
    # @param cert_file [String, nil] path to client certificate PEM file
    # @param key_file [String, nil] path to client private key PEM file
    # @param ca_file [String, nil] path to CA certificate PEM file
    # @param insecure_skip_verify [Boolean] skip server certificate verification (default: +false+)
    def initialize(enabled: false, cert_file: nil, key_file: nil, ca_file: nil,
                   insecure_skip_verify: false)
      @enabled = enabled
      @cert_file = cert_file
      @key_file = key_file
      @ca_file = ca_file
      @insecure_skip_verify = insecure_skip_verify
    end
  end

  # gRPC keepalive configuration for long-lived connections.
  #
  # When enabled (default), periodic pings are sent to detect dead
  # connections and keep firewalls/load-balancers from closing idle
  # connections.
  #
  # @example Aggressive keepalive for flaky networks
  #   keepalive = KubeMQ::KeepAliveConfig.new(
  #     ping_interval_seconds: 5,
  #     ping_timeout_seconds: 3
  #   )
  #
  # @see Configuration
  class KeepAliveConfig
    # @!attribute [rw] enabled
    #   @return [Boolean] whether gRPC keepalive is enabled (default: +true+)
    # @!attribute [rw] ping_interval_seconds
    #   @return [Integer] seconds between keepalive pings (default: +10+)
    # @!attribute [rw] ping_timeout_seconds
    #   @return [Integer] seconds to wait for a ping response before considering
    #     the connection dead (default: +5+)
    # @!attribute [rw] permit_without_calls
    #   @return [Boolean] send pings even when there are no active RPCs (default: +true+)
    attr_accessor :enabled, :ping_interval_seconds, :ping_timeout_seconds, :permit_without_calls

    # Creates a new keepalive configuration.
    #
    # @param enabled [Boolean] whether gRPC keepalive is enabled (default: +true+)
    # @param ping_interval_seconds [Integer] seconds between keepalive pings (default: +10+)
    # @param ping_timeout_seconds [Integer] seconds to wait for a ping response (default: +5+)
    # @param permit_without_calls [Boolean] send pings without active RPCs (default: +true+)
    def initialize(enabled: true, ping_interval_seconds: 10, ping_timeout_seconds: 5,
                   permit_without_calls: true)
      @enabled = enabled
      @ping_interval_seconds = Integer(ping_interval_seconds)
      @ping_timeout_seconds = Integer(ping_timeout_seconds)
      @permit_without_calls = permit_without_calls
    end
  end

  # Reconnection policy with exponential backoff and jitter.
  #
  # When enabled (default), the transport automatically reconnects after
  # transient failures. The delay between attempts is computed as:
  #
  #   delay = min(base_interval * multiplier^(attempt-1), max_delay) +/- jitter
  #
  # @example Custom reconnect policy
  #   policy = KubeMQ::ReconnectPolicy.new(
  #     base_interval: 2.0,
  #     max_delay: 60.0,
  #     max_attempts: 10
  #   )
  #
  # @see Configuration
  class ReconnectPolicy
    # @!attribute [rw] enabled
    #   @return [Boolean] whether auto-reconnect is enabled (default: +true+)
    # @!attribute [rw] base_interval
    #   @return [Float] initial delay between reconnect attempts in seconds (default: +1.0+)
    # @!attribute [rw] multiplier
    #   @return [Float] multiplier applied to delay after each attempt (default: +2.0+)
    # @!attribute [rw] max_delay
    #   @return [Float] maximum delay cap in seconds (default: +30.0+)
    # @!attribute [rw] jitter_percent
    #   @return [Float] jitter as a fraction of the computed delay (default: +0.25+)
    # @!attribute [rw] max_attempts
    #   @return [Integer] maximum reconnect attempts; +0+ means unlimited (default: +0+)
    attr_accessor :enabled, :base_interval, :multiplier, :max_delay, :jitter_percent, :max_attempts

    # Creates a new reconnect policy.
    #
    # @param enabled [Boolean] whether auto-reconnect is enabled (default: +true+)
    # @param base_interval [Float] initial delay in seconds (default: +1.0+)
    # @param multiplier [Float] backoff multiplier (default: +2.0+)
    # @param max_delay [Float] maximum delay cap in seconds (default: +30.0+)
    # @param jitter_percent [Float] jitter fraction of the computed delay (default: +0.25+)
    # @param max_attempts [Integer] maximum attempts; +0+ for unlimited (default: +0+)
    def initialize(enabled: true, base_interval: 1.0, multiplier: 2.0, max_delay: 30.0,
                   jitter_percent: 0.25, max_attempts: 0)
      @enabled = enabled
      @base_interval = Float(base_interval)
      @multiplier = Float(multiplier)
      @max_delay = Float(max_delay)
      @jitter_percent = Float(jitter_percent)
      @max_attempts = Integer(max_attempts)
    end
  end

  # Central configuration for KubeMQ client connections.
  #
  # Resolved in precedence order:
  # 1. Constructor keyword arguments
  # 2. Global {KubeMQ.configure} block
  # 3. Environment variables (+KUBEMQ_ADDRESS+, +KUBEMQ_AUTH_TOKEN+)
  # 4. Built-in defaults
  #
  # @example Full configuration
  #   config = KubeMQ::Configuration.new(
  #     address: "broker.example.com:50000",
  #     client_id: "order-service",
  #     auth_token: ENV["KUBEMQ_AUTH_TOKEN"],
  #     tls: KubeMQ::TLSConfig.new(enabled: true, ca_file: "/certs/ca.pem"),
  #     log_level: :info
  #   )
  #   client = KubeMQ::PubSubClient.new(config: config)
  #
  # @see TLSConfig
  # @see KeepAliveConfig
  # @see ReconnectPolicy
  class Configuration
    # @!attribute [rw] address
    #   @return [String] broker host:port (default: +ENV["KUBEMQ_ADDRESS"]+ or +"localhost:50000"+)
    # @!attribute [rw] client_id
    #   @return [String] unique client identifier (default: auto-generated)
    # @!attribute [rw] auth_token
    #   @return [String, nil] bearer authentication token
    # @!attribute [rw] tls
    #   @return [TLSConfig] TLS/mTLS configuration
    # @!attribute [rw] keepalive
    #   @return [KeepAliveConfig] gRPC keepalive settings
    # @!attribute [rw] reconnect_policy
    #   @return [ReconnectPolicy] auto-reconnect policy
    # @!attribute [rw] max_send_size
    #   @return [Integer] maximum outbound message size in bytes (default: 104_857_600 / 100 MB)
    # @!attribute [rw] max_receive_size
    #   @return [Integer] maximum inbound message size in bytes (default: 104_857_600 / 100 MB)
    # @!attribute [rw] log_level
    #   @return [Symbol] log level — +:debug+, +:info+, +:warn+, +:error+ (default: +:warn+)
    # @!attribute [rw] default_timeout
    #   @return [Integer] default gRPC deadline in seconds (default: +30+)
    attr_accessor :address, :client_id, :auth_token,
                  :tls, :keepalive, :reconnect_policy,
                  :max_send_size, :max_receive_size,
                  :log_level, :default_timeout

    # Creates a new configuration with the given options.
    #
    # Unspecified options fall back to environment variables and then to
    # built-in defaults.
    #
    # @param address [String, nil] broker host:port (default: +ENV["KUBEMQ_ADDRESS"]+ or +"localhost:50000"+)
    # @param client_id [String, nil] unique client identifier (default: auto-generated)
    # @param auth_token [String, nil] bearer authentication token
    # @param tls [TLSConfig, nil] TLS/mTLS configuration (default: TLS disabled)
    # @param keepalive [KeepAliveConfig, nil] gRPC keepalive settings (default: enabled)
    # @param reconnect_policy [ReconnectPolicy, nil] auto-reconnect policy (default: enabled)
    # @param max_send_size [Integer] maximum outbound message size in bytes (default: 100 MB)
    # @param max_receive_size [Integer] maximum inbound message size in bytes (default: 100 MB)
    # @param log_level [Symbol] log level — +:debug+, +:info+, +:warn+, +:error+ (default: +:warn+)
    # @param default_timeout [Integer] default gRPC deadline in seconds (default: +30+)
    def initialize(address: nil, client_id: nil, auth_token: nil,
                   tls: nil, keepalive: nil, reconnect_policy: nil,
                   max_send_size: 104_857_600, max_receive_size: 104_857_600,
                   log_level: :warn, default_timeout: 30)
      @address = address || ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
      @client_id = client_id || "kubemq-ruby-#{SecureRandom.hex(4)}"
      @auth_token = auth_token || ENV.fetch('KUBEMQ_AUTH_TOKEN', nil)
      @tls = tls || TLSConfig.new
      @keepalive = keepalive || KeepAliveConfig.new
      @reconnect_policy = reconnect_policy || ReconnectPolicy.new
      @max_send_size = max_send_size
      @max_receive_size = max_receive_size
      @log_level = log_level
      @default_timeout = Integer(default_timeout)
    end

    # Returns a developer-friendly string with the auth token redacted.
    #
    # @return [String]
    def inspect
      token_display = @auth_token ? '[REDACTED]' : 'nil'
      "#<#{self.class} address=#{@address.inspect} client_id=#{@client_id.inspect} auth_token=#{token_display}>"
    end

    # Validates this configuration and raises on invalid settings.
    #
    # Checks that +address+ is present and that TLS cert/key files are
    # provided as a pair when TLS is enabled.
    #
    # @return [Boolean] +true+ if the configuration is valid
    #
    # @raise [ConfigurationError] if +address+ is nil or empty
    # @raise [ConfigurationError] if TLS +cert_file+ is set without +key_file+ or vice versa
    # rubocop:disable Naming/PredicateMethod -- bang API: raises on invalid config or returns true
    def validate!
      raise ConfigurationError, 'address is required' if @address.nil? || @address.empty?
      if @tls.enabled && @tls.cert_file && !@tls.key_file
        raise ConfigurationError, 'TLS key_file is required when cert_file is set'
      end
      if @tls.enabled && @tls.key_file && !@tls.cert_file
        raise ConfigurationError, 'TLS cert_file is required when key_file is set'
      end

      true
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
