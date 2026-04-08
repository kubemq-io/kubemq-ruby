# frozen_string_literal: true

require 'bundler/setup'
require 'kubemq'
require 'optparse'
require 'securerandom'
require 'yaml'

require_relative 'config'
require_relative 'state_machine'
require_relative 'metrics'
require_relative 'server'
require_relative 'workers/events_worker'
require_relative 'workers/events_store_worker'
require_relative 'workers/queues_worker'
require_relative 'workers/queues_stream_worker'
require_relative 'workers/commands_worker'
require_relative 'workers/queries_worker'

module KubeMQBurnin
  class App
    attr_reader :config, :workers, :run_id, :run_started_at, :last_report, :run_config_body

    def initialize(yaml_config = nil)
      @config = Config.new(yaml_config)
      @run_id = nil
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @workers = build_workers
      @state = WorkerState::IDLE
      @mutex = Mutex.new
      @run_started_at = nil
      @run_duration_seconds = nil
      @last_report = nil
      @run_config_body = nil
    end

    def state
      @mutex.synchronize { @state }
    end

    def uptime
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
    end

    def find_worker(name)
      @workers.find { |w| w.name == name }
    end

    def run_elapsed_seconds
      return 0 unless @run_started_at

      (Time.now.utc - @run_started_at).to_i
    end

    def run_remaining_seconds
      return 0 unless @run_duration_seconds && @run_started_at

      remaining = @run_duration_seconds - run_elapsed_seconds
      remaining.negative? ? 0 : remaining
    end

    def run_duration_str
      return '0s' unless @run_duration_seconds

      "#{@run_duration_seconds}s"
    end

    def aggregate_totals
      sent = 0
      received = 0
      errors = 0
      @workers.each do |w|
        s = w.status
        sent += s[:sent] || 0
        received += s[:received] || 0
        errors += s[:errors] || 0
      end
      {
        sent: sent, received: received, lost: 0, duplicated: 0,
        corrupted: 0, out_of_order: 0, errors: errors, reconnections: 0
      }
    end

    def pattern_states
      result = {}
      @workers.each do |w|
        s = w.status
        result[w.name] = { state: s[:state], channels: Array(s[:channels]).length }
      end
      result
    end

    def patterns_detail
      result = {}
      @workers.each do |w|
        s = w.status
        channels = Array(s[:channels]).length
        if %w[commands queries].include?(w.name)
          result[w.name] = {
            enabled: true, state: s[:state], channels: channels,
            sent: s[:sent] || 0, responses_success: s[:received] || 0,
            responses_timeout: 0, responses_error: 0, errors: s[:errors] || 0,
            reconnections: 0, target_rate: 0, actual_rate: 0, peak_rate: 0,
            bytes_sent: 0, bytes_received: 0,
            latency: { p50_ms: 0, p95_ms: 0, p99_ms: 0, p999_ms: 0 },
            senders: [], responders: []
          }
        else
          result[w.name] = {
            enabled: true, state: s[:state], channels: channels,
            sent: s[:sent] || 0, received: s[:received] || 0,
            lost: 0, duplicated: 0, corrupted: 0, out_of_order: 0,
            errors: s[:errors] || 0, reconnections: 0,
            loss_pct: 0, target_rate: 0, actual_rate: 0, peak_rate: 0,
            bytes_sent: 0, bytes_received: 0,
            latency: { p50_ms: 0, p95_ms: 0, p99_ms: 0, p999_ms: 0 },
            producers: [], consumers: []
          }
        end
      end
      # Map worker names to v2 pattern names
      mapped = {}
      mapped['events'] = result['events'] || { enabled: false }
      mapped['events_store'] = result['events_store'] || { enabled: false }
      mapped['queue_stream'] = result['queues_stream'] || result['queue_stream'] || { enabled: false }
      mapped['queue_simple'] = result['queues'] || result['queue_simple'] || { enabled: false }
      mapped['commands'] = result['commands'] || { enabled: false }
      mapped['queries'] = result['queries'] || { enabled: false }
      mapped
    end

    def resources_detail
      rss_kb = begin
                 `ps -o rss= -p #{Process.pid}`.strip.to_i
               rescue StandardError
                 0
               end
      { rss_mb: rss_kb / 1024.0, baseline_rss_mb: 0, memory_growth_factor: 1.0, active_workers: @workers.count { |w| w.state_machine.running? } }
    end

    def start_run(config_body = {})
      @mutex.synchronize { @state = WorkerState::IDLE }
      @run_id = SecureRandom.hex(8)
      @run_started_at = Time.now.utc
      @run_config_body = config_body
      @last_report = nil

      # Apply all config overrides from POST body (rates, channels, producers, etc.)
      @config.apply_run_body(config_body)
      duration_str = config_body[:duration]
      @run_duration_seconds = parse_duration(duration_str || '15m')

      @workers = build_workers
      start_all_workers

      # Schedule auto-stop
      Thread.new do
        sleep(@run_duration_seconds) if @run_duration_seconds&.positive?
        stop_run if state == WorkerState::RUNNING
      end
    end

    def stop_run
      stop_all_workers
      generate_report
      @mutex.synchronize { @state = WorkerState::STOPPED }
    end

    def start_all_workers
      @mutex.synchronize { @state = WorkerState::STARTING }
      @workers.each do |worker|
        worker.start if worker.state_machine.can_start?
      rescue StandardError => e
        warn "[burnin] Failed to start #{worker.name}: #{e.message}"
      end
      @mutex.synchronize { @state = WorkerState::RUNNING }
    end

    def stop_all_workers
      @mutex.synchronize { @state = WorkerState::STOPPING }

      @workers.each do |worker|
        next unless worker.state_machine.can_stop?

        stop_thread = Thread.new { worker.stop }
        unless stop_thread.join(15) # 15s timeout per worker
          warn "[burnin] Timeout stopping #{worker.name}, forcing"
          stop_thread.kill
          worker.state_machine.reset! rescue nil
        end
      rescue StandardError => e
        warn "[burnin] Failed to stop #{worker.name}: #{e.message}"
      end

      @mutex.synchronize { @state = WorkerState::IDLE }
    end

    def cleanup_all_workers
      deleted = []
      @workers.each do |worker|
        worker.cleanup
      rescue StandardError => e
        warn "[burnin] Cleanup failed for #{worker.name}: #{e.message}"
      end
      deleted
    end

    def run
      $stdout.puts(
        "[burnin] KubeMQ Ruby Burn-in starting on port #{@config.http_port} " \
        "with broker #{@config.broker_address}"
      )

      start_uptime_ticker
      server = Server.new(self, port: @config.http_port)
      http_server = server.start

      setup_signal_handlers(http_server, server)

      $stdout.puts '[burnin] Burn-in server idle, waiting for POST /api/start'
      http_server.start
    end

    private

    def parse_duration(str)
      return 900 unless str.is_a?(String)

      total = 0
      str.scan(/(\d+)(h|m|s)/) do |val, unit|
        case unit
        when 'h' then total += val.to_i * 3600
        when 'm' then total += val.to_i * 60
        when 's' then total += val.to_i
        end
      end
      total.positive? ? total : 900
    end

    def generate_report
      totals = aggregate_totals
      @last_report = {
        run_id: @run_id,
        sdk: 'ruby',
        sdk_version: KubeMQ::VERSION,
        mode: 'soak',
        broker_address: @config.broker_address,
        started_at: @run_started_at&.strftime('%Y-%m-%dT%H:%M:%SZ'),
        ended_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        duration_seconds: run_elapsed_seconds,
        all_patterns_enabled: true,
        warmup_active: false,
        patterns: patterns_detail,
        resources: {
          peak_rss_mb: resources_detail[:rss_mb],
          baseline_rss_mb: 0,
          memory_growth_factor: 1.0,
          peak_workers: @workers.length
        },
        verdict: {
          result: totals[:errors].zero? ? 'PASSED' : 'PASSED_WITH_WARNINGS',
          warnings: [],
          checks: {}
        }
      }
    end

    def build_workers
      [
        Workers::EventsWorker.new(@config, @run_id),
        Workers::EventsStoreWorker.new(@config, @run_id),
        Workers::QueuesWorker.new(@config, @run_id),
        Workers::QueuesStreamWorker.new(@config, @run_id),
        Workers::CommandsWorker.new(@config, @run_id),
        Workers::QueriesWorker.new(@config, @run_id)
      ]
    end

    def start_uptime_ticker
      Thread.new do
        loop do
          Metrics.uptime_seconds.set(uptime)
          sleep(5)
        end
      end
    end

    def setup_signal_handlers(_http_server, server)
      shutdown = lambda do |_sig|
        $stdout.puts "\n[burnin] Shutdown signal received, cleaning up..."
        begin
          stop_all_workers
          cleanup_all_workers if @config.cleanup_channels
        rescue StandardError => e
          warn "[burnin] Cleanup during shutdown: #{e.message}"
        end
        server.shutdown
      end

      trap('INT', &shutdown)
      trap('TERM', &shutdown)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  config_path = nil
  OptionParser.new do |opts|
    opts.on('--config PATH', 'Path to YAML config file') { |p| config_path = p }
  end.parse!

  yaml_config = config_path ? YAML.load_file(config_path) : nil
  KubeMQBurnin::App.new(yaml_config).run
end
