# frozen_string_literal: true

module KubeMQBurnin
  class Config
    DEFAULTS = {
      broker_address: 'localhost:50000',
      http_port: 8888,
      events_rate: 10,
      events_channels: 1,
      events_store_rate: 10,
      events_store_channels: 1,
      queues_rate: 10,
      queues_channels: 1,
      queues_stream_rate: 10,
      queues_stream_channels: 1,
      commands_rate: 10,
      commands_channels: 1,
      queries_rate: 10,
      queries_channels: 1,
      message_size: 256,
      poll_max_messages: 10,
      poll_wait_timeout: 5,
      rpc_timeout: 10,
      drain_timeout: 10,
      cleanup_channels: true
    }.freeze

    attr_accessor :broker_address, :http_port,
                  :events_rate, :events_channels,
                  :events_producers_per_channel, :events_consumers_per_channel,
                  :events_store_rate, :events_store_channels,
                  :events_store_producers_per_channel, :events_store_consumers_per_channel,
                  :queues_rate, :queues_channels,
                  :queues_producers_per_channel, :queues_consumers_per_channel,
                  :queues_stream_rate, :queues_stream_channels,
                  :queues_stream_producers_per_channel, :queues_stream_consumers_per_channel,
                  :commands_rate, :commands_channels,
                  :commands_senders_per_channel, :commands_responders_per_channel,
                  :queries_rate, :queries_channels,
                  :queries_senders_per_channel, :queries_responders_per_channel,
                  :message_size, :poll_max_messages, :poll_wait_timeout,
                  :rpc_timeout, :drain_timeout, :cleanup_channels

    # rubocop:disable Metrics/AbcSize -- one assignment per env-backed setting
    def initialize(yaml_config = nil)
      @broker_address = yaml_config&.dig('broker', 'address') ||
                        env('KUBEMQ_BROKER_ADDRESS', DEFAULTS[:broker_address])
      @http_port = yaml_config&.dig('metrics', 'port') ||
                   env_int('BURNIN_HTTP_PORT', DEFAULTS[:http_port])
      @events_rate = env_int('BURNIN_EVENTS_RATE', DEFAULTS[:events_rate])
      @events_channels = env_int('BURNIN_EVENTS_CHANNELS', DEFAULTS[:events_channels])
      @events_producers_per_channel = 1
      @events_consumers_per_channel = 1
      @events_store_rate = env_int('BURNIN_EVENTS_STORE_RATE', DEFAULTS[:events_store_rate])
      @events_store_channels = env_int('BURNIN_EVENTS_STORE_CHANNELS', DEFAULTS[:events_store_channels])
      @events_store_producers_per_channel = 1
      @events_store_consumers_per_channel = 1
      @queues_rate = env_int('BURNIN_QUEUES_RATE', DEFAULTS[:queues_rate])
      @queues_channels = env_int('BURNIN_QUEUES_CHANNELS', DEFAULTS[:queues_channels])
      @queues_producers_per_channel = 1
      @queues_consumers_per_channel = 1
      @queues_stream_rate = env_int('BURNIN_QUEUES_STREAM_RATE', DEFAULTS[:queues_stream_rate])
      @queues_stream_channels = env_int('BURNIN_QUEUES_STREAM_CHANNELS', DEFAULTS[:queues_stream_channels])
      @queues_stream_producers_per_channel = 1
      @queues_stream_consumers_per_channel = 1
      @commands_rate = env_int('BURNIN_COMMANDS_RATE', DEFAULTS[:commands_rate])
      @commands_channels = env_int('BURNIN_COMMANDS_CHANNELS', DEFAULTS[:commands_channels])
      @commands_senders_per_channel = 1
      @commands_responders_per_channel = 1
      @queries_rate = env_int('BURNIN_QUERIES_RATE', DEFAULTS[:queries_rate])
      @queries_channels = env_int('BURNIN_QUERIES_CHANNELS', DEFAULTS[:queries_channels])
      @queries_senders_per_channel = 1
      @queries_responders_per_channel = 1
      @message_size = env_int('BURNIN_MESSAGE_SIZE', DEFAULTS[:message_size])
      @poll_max_messages = env_int('BURNIN_POLL_MAX_MESSAGES', DEFAULTS[:poll_max_messages])
      @poll_wait_timeout = env_int('BURNIN_POLL_WAIT_TIMEOUT', DEFAULTS[:poll_wait_timeout])
      @rpc_timeout = env_int('BURNIN_RPC_TIMEOUT', DEFAULTS[:rpc_timeout])
      @drain_timeout = env_int('BURNIN_DRAIN_TIMEOUT', DEFAULTS[:drain_timeout])
      @cleanup_channels = env_bool('BURNIN_CLEANUP_CHANNELS', DEFAULTS[:cleanup_channels])
    end
    # rubocop:enable Metrics/AbcSize

    def to_h
      {
        broker_address: @broker_address,
        http_port: @http_port,
        events: { rate: @events_rate, channels: @events_channels },
        events_store: { rate: @events_store_rate, channels: @events_store_channels },
        queues: { rate: @queues_rate, channels: @queues_channels },
        queues_stream: { rate: @queues_stream_rate, channels: @queues_stream_channels },
        commands: { rate: @commands_rate, channels: @commands_channels },
        queries: { rate: @queries_rate, channels: @queries_channels },
        message_size: @message_size,
        poll_max_messages: @poll_max_messages,
        poll_wait_timeout: @poll_wait_timeout,
        rpc_timeout: @rpc_timeout,
        drain_timeout: @drain_timeout,
        cleanup_channels: @cleanup_channels
      }
    end

    def update_from_hash(hash)
      hash.each do |key, value|
        setter = :"#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end

    # Apply overrides from the POST /run/start JSON body (v2 format)
    def apply_run_body(body)
      if body.dig(:broker, :address)
        @broker_address = body[:broker][:address]
      end
      apply_pattern_config(body, :events, :events)
      apply_pattern_config(body, :events_store, :events_store)
      apply_pattern_config(body, :queue_simple, :queues)
      apply_pattern_config(body, :queue_stream, :queues_stream)
      apply_rpc_pattern_config(body, :commands, :commands)
      apply_rpc_pattern_config(body, :queries, :queries)
      @message_size = body.dig(:message, :size_bytes) || @message_size
      @poll_max_messages = body.dig(:queue, :poll_max_messages) || @poll_max_messages
      @poll_wait_timeout = body.dig(:queue, :poll_wait_timeout_seconds) || @poll_wait_timeout
      @rpc_timeout = (body.dig(:rpc, :timeout_ms) || @rpc_timeout * 1000) / 1000
      @drain_timeout = body.dig(:shutdown, :drain_timeout_seconds) || @drain_timeout
      cleanup = body.dig(:shutdown, :cleanup_channels)
      @cleanup_channels = cleanup unless cleanup.nil?
    end

    private

    def apply_pattern_config(body, body_key, config_prefix)
      pat = body.dig(:patterns, body_key) || {}
      send(:"#{config_prefix}_rate=", pat[:rate]) if pat[:rate]
      send(:"#{config_prefix}_channels=", pat[:channels]) if pat[:channels]
      send(:"#{config_prefix}_producers_per_channel=", pat[:producers_per_channel]) if pat[:producers_per_channel]
      send(:"#{config_prefix}_consumers_per_channel=", pat[:consumers_per_channel]) if pat[:consumers_per_channel]
    end

    def apply_rpc_pattern_config(body, body_key, config_prefix)
      pat = body.dig(:patterns, body_key) || {}
      send(:"#{config_prefix}_rate=", pat[:rate]) if pat[:rate]
      send(:"#{config_prefix}_channels=", pat[:channels]) if pat[:channels]
      send(:"#{config_prefix}_senders_per_channel=", pat[:senders_per_channel]) if pat[:senders_per_channel]
      send(:"#{config_prefix}_responders_per_channel=", pat[:responders_per_channel]) if pat[:responders_per_channel]
    end

    def env(name, default)
      ENV.fetch(name, default.to_s)
    end

    def env_int(name, default)
      ENV.fetch(name, default.to_s).to_i
    end

    def env_bool(name, default)
      val = ENV.fetch(name, nil)
      return default if val.nil?

      %w[true 1 yes].include?(val.downcase)
    end
  end
end
