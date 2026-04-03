# frozen_string_literal: true

require 'webrick'
require 'json'
require_relative 'metrics'

module KubeMQBurnin
  class Server
    def initialize(app, port:)
      @app = app
      @port = port
      @server = nil
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
      mount_health_ready_metrics
      mount_api_status_start_stop
      mount_api_config_route
      mount_api_workers_route
      mount_api_cleanup_route
    end

    def mount_health_ready_metrics
      @server.mount_proc('/health') { |req, res| guard_method(req, res, 'GET') { health(res) } }
      @server.mount_proc('/ready') { |req, res| guard_method(req, res, 'GET') { ready(res) } }
      @server.mount_proc('/metrics') { |req, res| guard_method(req, res, 'GET') { metrics_endpoint(res) } }
    end

    def mount_api_status_start_stop
      @server.mount_proc('/api/status') { |req, res| guard_method(req, res, 'GET') { api_status(res) } }
      @server.mount_proc('/api/start') { |req, res| guard_method(req, res, 'POST') { api_start(req, res) } }
      @server.mount_proc('/api/stop') { |req, res| guard_method(req, res, 'POST') { api_stop(res) } }
    end

    def mount_api_config_route
      @server.mount_proc('/api/config') do |req, res|
        case req.request_method
        when 'GET' then api_get_config(res)
        when 'POST' then api_set_config(req, res)
        else method_not_allowed(res)
        end
      end
    end

    def mount_api_workers_route
      @server.mount_proc('/api/workers') do |req, res|
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

    def dispatch_worker_subresource(name, action, res)
      case action
      when 'start' then api_start_worker(name, res)
      when 'stop' then api_stop_worker(name, res)
      else not_found(res)
      end
    end

    def mount_api_cleanup_route
      @server.mount_proc('/api/cleanup') { |req, res| guard_method(req, res, 'POST') { api_cleanup(res) } }
    end

    # --- Endpoint handlers ---

    def health(res)
      json_response(res, 200, { status: 'ok' })
    end

    def ready(res)
      json_response(res, 200, { ready: true, state: @app.state })
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
  end
end
