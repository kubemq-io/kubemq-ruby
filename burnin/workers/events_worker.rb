# frozen_string_literal: true

require_relative '../state_machine'
require_relative '../metrics'

module KubeMQBurnin
  module Workers
    class EventsWorker
      WORKER_NAME = 'events'

      attr_reader :name, :state_machine

      def initialize(config, run_id)
        @config = config
        @run_id = run_id
        @name = WORKER_NAME
        @state_machine = StateMachine.new
        @threads = []
        @cancel = false
        @mutex = Mutex.new
        @publisher = nil
        @subscriber = nil
        @cancellation_token = nil
        @sent_count = 0
        @received_count = 0
        @last_rate_time = nil
        @last_sent_count = 0
      end

      def start
        return unless @state_machine.can_start?

        @state_machine.transition_to!(WorkerState::STARTING)
        @cancel = false
        @sent_count = 0
        @received_count = 0
        @last_rate_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @last_sent_count = 0

        channel_names = generate_channel_names
        @publisher = KubeMQ::PubSubClient.new(address: @config.broker_address,
                                              client_id: 'burnin-events-pub')
        @subscriber = KubeMQ::PubSubClient.new(address: @config.broker_address,
                                               client_id: 'burnin-events-sub')

        create_channels(channel_names)
        start_subscribers(channel_names)
        sleep(0.5) # allow subscribers to register before publishing
        start_publishers(channel_names)

        @state_machine.transition_to!(WorkerState::RUNNING)
        Metrics.worker_state.set(1, labels: { worker: @name })
      rescue StandardError => e
        @state_machine.reset!
        Metrics.errors_total.increment(labels: { worker: @name, error_type: 'start' })
        raise e
      end

      def stop
        return unless @state_machine.can_stop?

        @state_machine.transition_to!(WorkerState::STOPPING)
        @cancel = true
        sleep(1.0) # let publishers finish and in-flight messages drain before disconnecting subscriber
        @cancellation_token&.cancel

        @threads.each { |t| t.join(@config.drain_timeout) }
        @threads.clear

        @publisher&.close
        @subscriber&.close
        @publisher = nil
        @subscriber = nil

        @state_machine.transition_to!(WorkerState::STOPPED)
        Metrics.worker_state.set(2, labels: { worker: @name })
        @state_machine.transition_to!(WorkerState::IDLE)
        Metrics.worker_state.set(0, labels: { worker: @name })
      rescue StandardError => e
        @state_machine.reset!
        Metrics.errors_total.increment(labels: { worker: @name, error_type: 'stop' })
        raise e
      end

      def cleanup
        generate_channel_names.each do |ch|
          client = KubeMQ::PubSubClient.new(address: @config.broker_address,
                                            client_id: 'burnin-events-cleanup')
          client.delete_events_channel(channel_name: ch)
          Metrics.channels_deleted_total.increment(labels: { type: 'events' })
          client.close
        rescue StandardError
          # best-effort cleanup
        end
      end

      def status
        {
          name: @name,
          state: @state_machine.state,
          sent: @sent_count,
          received: @received_count,
          channels: generate_channel_names
        }
      end

      private

      def generate_channel_names
        (1..@config.events_channels).map { |i| "ruby_burnin_#{@run_id}_events_#{i}" }
      end

      def create_channels(channel_names)
        channel_names.each do |ch|
          @publisher.create_events_channel(channel_name: ch)
          Metrics.channels_created_total.increment(labels: { type: 'events' })
        rescue StandardError
          # channel may already exist
        end
      end

      def start_subscribers(channel_names)
        @cancellation_token = KubeMQ::CancellationToken.new
        channel_names.each do |ch|
          sub = KubeMQ::PubSub::EventsSubscription.new(channel: ch)
          thread = @subscriber.subscribe_to_events(
            sub,
            cancellation_token: @cancellation_token,
            on_error: ->(err) { record_error(ch, 'subscribe', err) }
          ) do |event|
            @mutex.synchronize { @received_count += 1 }
            body_size = event.body&.bytesize || 0
            Metrics.messages_received_total.increment(labels: { worker: @name, channel: ch })
            Metrics.messages_received_bytes_total.increment(by: body_size, labels: { worker: @name, channel: ch })
          end
          @threads << thread
        end
      end

      def start_publishers(channel_names)
        channel_names.each do |ch|
          thread = Thread.new do
            rate_limited_loop(@config.events_rate) do
              break if @cancel

              start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              payload = generate_payload
              msg = KubeMQ::PubSub::EventMessage.new(channel: ch, metadata: 'burnin', body: payload)
              @publisher.send_event(msg)

              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
              @mutex.synchronize { @sent_count += 1 }
              Metrics.messages_sent_total.increment(labels: { worker: @name, channel: ch })
              Metrics.messages_sent_bytes_total.increment(by: payload.bytesize, labels: { worker: @name, channel: ch })
              Metrics.send_duration_seconds.observe(elapsed, labels: { worker: @name })
              update_send_rate
            rescue StandardError => e
              record_error(ch, 'publish', e)
            end
          end
          @threads << thread
        end
      end

      def record_error(_channel, error_type, _err)
        Metrics.errors_total.increment(labels: { worker: @name, error_type: error_type })
      end

      def update_send_rate
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @mutex.synchronize do
          elapsed = now - (@last_rate_time || now)
          if elapsed >= 1.0
            rate = (@sent_count - @last_sent_count) / elapsed
            Metrics.send_rate.set(rate, labels: { worker: @name })
            @last_rate_time = now
            @last_sent_count = @sent_count
          end
        end
      end

      def rate_limited_loop(rate_per_second, &block)
        return if rate_per_second <= 0

        interval = 1.0 / rate_per_second
        next_send = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        until @cancel
          block.call
          next_send += interval
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep_time = next_send - now
          if sleep_time.positive?
            sleep(sleep_time)
          elsif now - next_send > 1.0
            next_send = now
          end
        end
      end

      def generate_payload
        Random.bytes(@config.message_size)
      end
    end
  end
end
