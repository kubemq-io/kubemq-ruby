# frozen_string_literal: true

require_relative '../state_machine'
require_relative '../metrics'

module KubeMQBurnin
  module Workers
    class CommandsWorker
      WORKER_NAME = 'commands'

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
        @responder = nil
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
        @sender = KubeMQ::CQClient.new(address: @config.broker_address,
                                       client_id: 'burnin-commands-send')
        @responder = KubeMQ::CQClient.new(address: @config.broker_address,
                                          client_id: 'burnin-commands-resp')

        create_channels(channel_names)
        start_responders(channel_names)
        sleep(0.5) # allow responders to register before sending
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
        sleep(1.0) # let senders finish and in-flight messages drain before disconnecting responder
        @cancellation_token&.cancel

        @threads.each { |t| t.join(@config.drain_timeout) }
        @threads.clear

        @sender&.close
        @responder&.close
        @sender = nil
        @responder = nil

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
          client = KubeMQ::CQClient.new(address: @config.broker_address,
                                        client_id: 'burnin-commands-cleanup')
          client.delete_commands_channel(channel_name: ch)
          Metrics.channels_deleted_total.increment(labels: { type: 'commands' })
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
        (1..@config.commands_channels).map { |i| "ruby_burnin_#{@run_id}_commands_#{i}" }
      end

      def create_channels(channel_names)
        channel_names.each do |ch|
          @sender.create_commands_channel(channel_name: ch)
          Metrics.channels_created_total.increment(labels: { type: 'commands' })
        rescue StandardError
          # channel may already exist
        end
      end

      def start_responders(channel_names)
        @cancellation_token = KubeMQ::CancellationToken.new
        channel_names.each do |ch|
          sub = KubeMQ::CQ::CommandsSubscription.new(channel: ch)
          thread = @responder.subscribe_to_commands(
            sub,
            cancellation_token: @cancellation_token,
            on_error: ->(err) { record_error(ch, 'subscribe', err) }
          ) do |cmd|
            response = KubeMQ::CQ::CommandResponseMessage.new(
              request_id: cmd.id,
              reply_channel: cmd.reply_channel,
              executed: true,
              metadata: 'burnin-ack'
            )
            @responder.send_response(response)
            @mutex.synchronize { @received_count += 1 }
            Metrics.messages_received_total.increment(labels: { worker: @name, channel: ch })
            Metrics.commands_executed_total.increment(labels: { worker: @name })
          end
          @threads << thread
        end
      end

      def start_senders(channel_names)
        channel_names.each do |ch|
          thread = Thread.new do
            rate_limited_loop(@config.commands_rate) { send_one_command(ch) }
          end
          @threads << thread
        end
      end

      def send_one_command(channel_name)
        return if @cancel

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        payload = generate_payload
        msg = KubeMQ::CQ::CommandMessage.new(
          channel: channel_name,
          timeout: @config.rpc_timeout * 1000,
          metadata: 'burnin',
          body: payload
        )
        result = @sender.send_command(msg)

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        if result.executed
          @mutex.synchronize { @sent_count += 1 }
          Metrics.messages_sent_total.increment(labels: { worker: @name, channel: channel_name })
          Metrics.messages_sent_bytes_total.increment(by: payload.bytesize,
                                                      labels: { worker: @name, channel: channel_name })
          Metrics.send_duration_seconds.observe(elapsed, labels: { worker: @name })
          update_send_rate
        else
          Metrics.commands_failed_total.increment(labels: { worker: @name })
          Metrics.errors_total.increment(labels: { worker: @name, error_type: 'command_failed' })
        end
      rescue StandardError
        Metrics.errors_total.increment(labels: { worker: @name, error_type: 'send' })
        Metrics.commands_failed_total.increment(labels: { worker: @name })
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
