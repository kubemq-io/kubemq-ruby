# frozen_string_literal: true

require_relative '../state_machine'
require_relative '../metrics'

module KubeMQBurnin
  module Workers
    class QueuesWorker
      WORKER_NAME = 'queues'

      attr_reader :name, :state_machine

      def initialize(config, run_id)
        @config = config
        @run_id = run_id
        @name = WORKER_NAME
        @state_machine = StateMachine.new
        @threads = []
        @cancel = false
        @mutex = Mutex.new
        @sender = nil
        @receiver = nil
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
        @sender = KubeMQ::QueuesClient.new(address: @config.broker_address,
                                           client_id: 'burnin-queues-send')
        @receiver = KubeMQ::QueuesClient.new(address: @config.broker_address,
                                             client_id: 'burnin-queues-recv')

        create_channels(channel_names)
        start_receivers(channel_names)
        sleep(0.5) # allow receivers to register before sending
        start_senders(channel_names)

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

        @threads.each { |t| t.join(@config.drain_timeout) }
        @threads.clear

        @sender&.close
        @receiver&.close
        @sender = nil
        @receiver = nil

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
          client = KubeMQ::QueuesClient.new(address: @config.broker_address,
                                            client_id: 'burnin-queues-cleanup')
          client.delete_queues_channel(channel_name: ch)
          Metrics.channels_deleted_total.increment(labels: { type: 'queues' })
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
        (1..@config.queues_channels).map { |i| "ruby_burnin_#{@run_id}_queues_#{i}" }
      end

      def create_channels(channel_names)
        channel_names.each do |ch|
          @sender.create_queues_channel(channel_name: ch)
          Metrics.channels_created_total.increment(labels: { type: 'queues' })
        rescue StandardError
          # channel may already exist
        end
      end

      def start_receivers(channel_names)
        channel_names.each do |ch|
          thread = Thread.new do
            until @cancel
              begin
                start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                messages = @receiver.receive_queue_messages(
                  channel: ch,
                  max_messages: @config.poll_max_messages,
                  wait_timeout_seconds: @config.poll_wait_timeout
                )
                elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                next if messages.empty?

                count = messages.size
                total_bytes = messages.sum { |m| m.body&.bytesize || 0 }
                @mutex.synchronize { @received_count += count }
                Metrics.messages_received_total.increment(by: count, labels: { worker: @name, channel: ch })
                Metrics.messages_received_bytes_total.increment(
                  by: total_bytes, labels: { worker: @name, channel: ch }
                )
                Metrics.receive_duration_seconds.observe(elapsed, labels: { worker: @name })
                Metrics.ack_total.increment(by: count, labels: { worker: @name })
              rescue StandardError
                Metrics.errors_total.increment(labels: { worker: @name, error_type: 'receive' })
                sleep(1) unless @cancel
              end
            end
          end
          @threads << thread
        end
      end

      def start_senders(channel_names)
        channel_names.each do |ch|
          thread = Thread.new do
            rate_limited_loop(@config.queues_rate) do
              break if @cancel

              start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              payload = generate_payload
              msg = KubeMQ::Queues::QueueMessage.new(channel: ch, metadata: 'burnin', body: payload)
              @sender.send_queue_message(msg)

              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
              @mutex.synchronize { @sent_count += 1 }
              Metrics.messages_sent_total.increment(labels: { worker: @name, channel: ch })
              Metrics.messages_sent_bytes_total.increment(by: payload.bytesize, labels: { worker: @name, channel: ch })
              Metrics.send_duration_seconds.observe(elapsed, labels: { worker: @name })
              update_send_rate
            rescue StandardError
              Metrics.errors_total.increment(labels: { worker: @name, error_type: 'send' })
            end
          end
          @threads << thread
        end
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
