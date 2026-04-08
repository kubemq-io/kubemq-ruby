# frozen_string_literal: true

require 'webrick'
require 'json'
require 'etc'
require_relative 'metrics'

module KubeMQBurnin
  BURNIN_VERSION = '2.0.0'
  BURNIN_SPEC_VERSION = '2'

  class Server
    def initialize(app, port:)
      @app = app
      @port = port
      @server = nil
      @boot_time = Time.now.utc
    end

    def start
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
        AccessLog: []
      )

      mount_endpoints
      @server
    end

    def shutdown
      @server&.shutdown
    end

    private

    def mount_endpoints
      mount_health_ready_info
      mount_broker_status
      mount_run_endpoints
      mount_cleanup_endpoint
      mount_api_status_start_stop
      mount_api_config_route
      mount_api_workers_route
      mount_api_cleanup_route
    end

    def mount_health_ready_info
      @server.mount_proc('/health') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { health(res) } } }
      @server.mount_proc('/ready') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { ready(res) } } }
      @server.mount_proc('/info') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { info(res) } } }
      @server.mount_proc('/metrics') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { metrics_endpoint(res) } } }
    end

    def mount_broker_status
      @server.mount_proc('/broker/status') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { broker_status(res) } } }
    end

    def mount_run_endpoints
      @server.mount_proc('/run/status') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { run_status(res) } } }
      @server.mount_proc('/run/start') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { run_start(req, res) } } }
      @server.mount_proc('/run/stop') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { run_stop(res) } } }
      @server.mount_proc('/run/report') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { run_report(res) } } }
      @server.mount_proc('/run/config') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { run_config(res) } } }
      @server.mount_proc('/run') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { run_detail(res) } } }
    end

    def mount_cleanup_endpoint
      @server.mount_proc('/cleanup') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { cleanup(res) } } }
    end

    def mount_api_status_start_stop
      @server.mount_proc('/api/status') { |req, res| with_cors(req, res) { guard_method(req, res, 'GET') { api_status(res) } } }
      @server.mount_proc('/api/start') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { api_start(req, res) } } }
      @server.mount_proc('/api/stop') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { api_stop(res) } } }
    end

    def mount_api_config_route
      @server.mount_proc('/api/config') do |req, res|
        with_cors(req, res) do
          case req.request_method
          when 'GET' then api_get_config(res)
          when 'POST' then api_set_config(req, res)
          else method_not_allowed(res)
          end
        end
      end
    end

    def mount_api_workers_route
      @server.mount_proc('/api/workers') do |req, res|
        with_cors(req, res) do
          parts = req.path.split('/').reject(&:empty?)
          case parts.length
          when 2
            guard_method(req, res, 'GET') { api_list_workers(res) }
          when 3
            guard_method(req, res, 'GET') { api_get_worker(parts[2], res) }
          when 4
            guard_method(req, res, 'POST') { dispatch_worker_subresource(parts[2], parts[3], res) }
          else
            not_found(res)
          end
        end
      end
    end

    def dispatch_worker_subresource(name, action, res)
      case action
      when 'start' then api_start_worker(name, res)
      when 'stop' then api_stop_worker(name, res)
      else not_found(res)
      end
    end

    def mount_api_cleanup_route
      @server.mount_proc('/api/cleanup') { |req, res| with_cors(req, res) { guard_method(req, res, 'POST') { api_cleanup(res) } } }
    end

    # --- Endpoint handlers ---

    def health(res)
      json_response(res, 200, { status: 'alive' })
    end

    def ready(res)
      state = @app.state
      case state
      when WorkerState::STARTING, WorkerState::STOPPING
        json_response(res, 503, { status: 'not_ready', state: state })
      else
        json_response(res, 200, { status: 'ready', state: state })
      end
    end

    def info(res)
      json_response(res, 200, {
                      sdk: 'ruby',
                      sdk_version: KubeMQ::VERSION,
                      burnin_version: BURNIN_VERSION,
                      burnin_spec_version: BURNIN_SPEC_VERSION,
                      os: detect_os,
                      arch: detect_arch,
                      runtime: "ruby #{RUBY_VERSION}",
                      cpus: Etc.nprocessors,
                      memory_total_mb: detect_memory_mb,
                      pid: Process.pid,
                      uptime_seconds: @app.uptime.round(1),
                      started_at: @boot_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                      state: @app.state,
                      broker_address: @app.config.broker_address
                    })
    end

    def broker_status(res)
      address = @app.config.broker_address
      begin
        client = KubeMQ::PubSubClient.new(address: address, client_id: 'burnin-ping')
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        server_info = client.ping
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0).round(2)
        client.close

        json_response(res, 200, {
                        connected: true,
                        address: address,
                        ping_latency_ms: latency_ms,
                        server_version: server_info.version,
                        last_ping_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
                      })
      rescue StandardError => e
        json_response(res, 200, {
                        connected: false,
                        address: address,
                        error: e.message
                      })
      end
    end

    # --- V2 /run/* endpoint handlers ---

    def run_status(res)
      state = @app.state
      if state == WorkerState::IDLE
        json_response(res, 200, { run_id: nil, state: 'idle' })
      elsif state == WorkerState::STARTING
        json_response(res, 200, {
                        run_id: @app.run_id,
                        state: 'starting',
                        started_at: @app.run_started_at&.strftime('%Y-%m-%dT%H:%M:%SZ'),
                        elapsed_seconds: @app.run_elapsed_seconds
                      })
      elsif [WorkerState::RUNNING, WorkerState::STOPPING, WorkerState::STOPPED].include?(state)
        totals = @app.aggregate_totals
        json_response(res, 200, {
                        run_id: @app.run_id,
                        state: state,
                        started_at: @app.run_started_at&.strftime('%Y-%m-%dT%H:%M:%SZ'),
                        elapsed_seconds: @app.run_elapsed_seconds,
                        remaining_seconds: @app.run_remaining_seconds,
                        warmup_active: false,
                        totals: totals,
                        pattern_states: @app.pattern_states
                      })
      else
        json_response(res, 200, { run_id: @app.run_id, state: 'error', error: 'unknown state' })
      end
    end

    def run_start(req, res)
      unless [WorkerState::IDLE, WorkerState::STOPPED].include?(@app.state)
        json_response(res, 409, {
                        message: 'A run is already in progress',
                        run_id: @app.run_id,
                        state: @app.state
                      })
        return
      end

      body = begin
               JSON.parse(req.body || '{}', symbolize_names: true)
             rescue JSON::ParserError
               {}
             end
      @app.start_run(body)
      json_response(res, 202, {
                      run_id: @app.run_id,
                      state: @app.state,
                      message: 'Run started'
                    })
    rescue StandardError => e
      json_response(res, 500, { message: e.message })
    end

    def run_stop(res)
      state = @app.state
      case state
      when WorkerState::RUNNING, WorkerState::STARTING
        Thread.new { @app.stop_run }
        json_response(res, 202, {
                        run_id: @app.run_id,
                        state: 'stopping',
                        message: 'Run stopping'
                      })
      when WorkerState::STOPPING
        json_response(res, 202, {
                        run_id: @app.run_id,
                        state: 'stopping',
                        message: 'Run already stopping'
                      })
      when WorkerState::STOPPED
        json_response(res, 202, {
                        run_id: @app.run_id,
                        state: 'stopped',
                        message: 'Run already stopped'
                      })
      when WorkerState::IDLE
        json_response(res, 202, {
                        run_id: @app.run_id,
                        state: 'idle',
                        message: 'No active run'
                      })
      else
        json_response(res, 409, {
                        message: 'Cannot stop in current state',
                        state: state
                      })
      end
    rescue StandardError => e
      json_response(res, 500, { message: e.message })
    end

    def run_detail(res)
      state = @app.state
      if state == WorkerState::IDLE
        json_response(res, 200, { run_id: nil, state: 'idle' })
      else
        json_response(res, 200, {
                        run_id: @app.run_id,
                        state: state,
                        mode: 'soak',
                        started_at: @app.run_started_at&.strftime('%Y-%m-%dT%H:%M:%SZ'),
                        elapsed_seconds: @app.run_elapsed_seconds,
                        remaining_seconds: @app.run_remaining_seconds,
                        duration: @app.run_duration_str,
                        warmup_active: false,
                        broker_address: @app.config.broker_address,
                        patterns: @app.patterns_detail,
                        resources: @app.resources_detail
                      })
      end
    end

    def run_report(res)
      report = @app.last_report
      if report
        json_response(res, 200, report)
      else
        json_response(res, 404, { message: 'No report available' })
      end
    end

    def run_config(res)
      if @app.state == WorkerState::IDLE
        json_response(res, 404, { message: 'No active run' })
      else
        json_response(res, 200, {
                        run_id: @app.run_id,
                        state: @app.state,
                        config: @app.run_config_body
                      })
      end
    end

    def cleanup(res)
      deleted = @app.cleanup_all_workers
      json_response(res, 200, {
                      deleted_channels: deleted || [],
                      failed_channels: [],
                      message: 'Cleanup complete'
                    })
    rescue StandardError => e
      json_response(res, 500, { message: e.message })
    end

    def metrics_endpoint(res)
      res.status = 200
      res['Content-Type'] = 'text/plain; version=0.0.4; charset=utf-8'
      res.body = Metrics.scrape
    end

    def api_status(res)
      json_response(res, 200, {
                      state: @app.state,
                      uptime_seconds: @app.uptime.to_i,
                      workers: @app.workers.map(&:status)
                    })
    end

    def api_start(_req, res)
      @app.start_all_workers
      json_response(res, 200, { status: 'started' })
    rescue StandardError => e
      json_response(res, 400, { error: e.message })
    end

    def api_stop(res)
      @app.stop_all_workers
      json_response(res, 200, { status: 'stopped' })
    rescue StandardError => e
      json_response(res, 400, { error: e.message })
    end

    def api_get_config(res)
      json_response(res, 200, @app.config.to_h)
    end

    def api_set_config(req, res)
      body = JSON.parse(req.body || '{}', symbolize_names: true)
      @app.config.update_from_hash(body)
      json_response(res, 200, { status: 'updated', config: @app.config.to_h })
    rescue JSON::ParserError => e
      json_response(res, 400, { error: "Invalid JSON: #{e.message}" })
    rescue StandardError => e
      json_response(res, 400, { error: e.message })
    end

    def api_list_workers(res)
      json_response(res, 200, { workers: @app.workers.map(&:status) })
    end

    def api_get_worker(name, res)
      worker = @app.find_worker(name)
      if worker
        json_response(res, 200, worker.status)
      else
        json_response(res, 404, { error: "Worker '#{name}' not found" })
      end
    end

    def api_start_worker(name, res)
      worker = @app.find_worker(name)
      if worker
        worker.start
        json_response(res, 200, { status: 'started', worker: worker.status })
      else
        json_response(res, 404, { error: "Worker '#{name}' not found" })
      end
    rescue StandardError => e
      json_response(res, 400, { error: e.message })
    end

    def api_stop_worker(name, res)
      worker = @app.find_worker(name)
      if worker
        worker.stop
        json_response(res, 200, { status: 'stopped', worker: worker.status })
      else
        json_response(res, 404, { error: "Worker '#{name}' not found" })
      end
    rescue StandardError => e
      json_response(res, 400, { error: e.message })
    end

    def api_cleanup(res)
      @app.cleanup_all_workers
      json_response(res, 200, { status: 'cleaned up' })
    rescue StandardError => e
      json_response(res, 500, { error: e.message })
    end

    # --- Helpers ---

    def json_response(res, status, body)
      res.status = status
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(body)
    end

    def with_cors(req, res)
      res['Access-Control-Allow-Origin'] = '*'
      res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
      res['Access-Control-Allow-Headers'] = 'Content-Type'
      if req.request_method == 'OPTIONS'
        res.status = 204
        return
      end
      yield
    end

    def guard_method(req, res, expected)
      if req.request_method == expected
        yield
      else
        method_not_allowed(res)
      end
    end

    def method_not_allowed(res)
      json_response(res, 405, { error: 'Method not allowed' })
    end

    def not_found(res)
      json_response(res, 404, { error: 'Not found' })
    end

    def detect_os
      case RUBY_PLATFORM
      when /darwin/i then 'darwin'
      when /linux/i then 'linux'
      when /mswin|mingw|cygwin/i then 'windows'
      when /freebsd/i then 'freebsd'
      else RUBY_PLATFORM
      end
    end

    def detect_arch
      case RUBY_PLATFORM
      when /arm64|aarch64/i then 'arm64'
      when /x86_64|x64|amd64/i then 'amd64'
      when /i[3-6]86/i then '386'
      when /arm/i then 'arm'
      else RUBY_PLATFORM
      end
    end

    # rubocop:disable Metrics/MethodLength -- platform-specific branching
    def detect_memory_mb
      case RUBY_PLATFORM
      when /darwin/i
        mem_bytes = `sysctl -n hw.memsize 2>/dev/null`.strip.to_i
        mem_bytes.positive? ? mem_bytes / (1024 * 1024) : 0
      when /linux/i
        File.readlines('/proc/meminfo').each do |line|
          if line.start_with?('MemTotal:')
            return line.split[1].to_i / 1024
          end
        end
        0
      else
        0
      end
    rescue StandardError
      0
    end
    # rubocop:enable Metrics/MethodLength
  end
end
