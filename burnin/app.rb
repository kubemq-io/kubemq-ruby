# frozen_string_literal: true

require 'bundler/setup'
require 'kubemq'

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
    attr_reader :config, :workers, :run_id

    def initialize
      @config = Config.new
      @run_id = SecureRandom.hex(4)
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @workers = build_workers
      @state = WorkerState::IDLE
      @mutex = Mutex.new
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

      # Phase 1: Stop producers first (senders)
      @workers.each do |worker|
        worker.stop if worker.state_machine.can_stop?
      rescue StandardError => e
        warn "[burnin] Failed to stop #{worker.name}: #{e.message}"
      end

      @mutex.synchronize { @state = WorkerState::IDLE }
    end

    def cleanup_all_workers
      @workers.each do |worker|
        worker.cleanup
      rescue StandardError => e
        warn "[burnin] Cleanup failed for #{worker.name}: #{e.message}"
      end
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

KubeMQBurnin::App.new.run if $PROGRAM_NAME == __FILE__
