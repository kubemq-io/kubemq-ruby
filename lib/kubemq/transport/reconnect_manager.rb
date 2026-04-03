# frozen_string_literal: true

module KubeMQ
  module Transport
    # Manages automatic reconnection with exponential backoff and jitter.
    #
    # Spawns a background thread that repeatedly invokes the reconnect procedure
    # until the connection succeeds or the maximum number of attempts is reached.
    # Backoff delay is computed as:
    #   delay = min(base_interval * multiplier^(attempt-1), max_delay) +/- jitter
    #
    # @api private
    #
    # @see GrpcTransport
    # @see ConnectionStateMachine
    # @see ReconnectPolicy
    class ReconnectManager
      # @return [Integer] current reconnect attempt counter (0 before first attempt)
      attr_reader :attempt

      # @param policy [ReconnectPolicy] backoff and retry settings
      # @param state_machine [ConnectionStateMachine] tracks connection lifecycle
      # @param reconnect_proc [Proc] callable that performs the actual reconnection
      # @param on_reconnected [Proc, nil] optional callback invoked after successful reconnection
      def initialize(policy:, state_machine:, reconnect_proc:, on_reconnected: nil)
        @policy = policy
        @state_machine = state_machine
        @reconnect_proc = reconnect_proc
        @on_reconnected = on_reconnected
        @attempt = 0
        @mutex = Mutex.new
        @thread = nil
        @stop_flag = false
      end

      # Starts the background reconnect loop. No-op if already running.
      #
      # @return [void]
      def start
        @mutex.synchronize do
          return if @thread&.alive?

          @stop_flag = false
          @attempt = 0
          @thread = Thread.new { reconnect_loop }
          @thread.name = 'kubemq-reconnect'
          @thread.abort_on_exception = false
        end
      end

      # Signals the reconnect loop to stop and waits up to 5 seconds for
      # the background thread to finish.
      #
      # @return [void]
      def stop
        @mutex.synchronize { @stop_flag = true }
        @thread&.join(5)
      end

      private

      def reconnect_loop
        loop do
          break if stopped? || @state_machine.closed?

          @mutex.synchronize { @attempt += 1 }

          if @policy.max_attempts.positive? && @attempt > @policy.max_attempts
            @state_machine.transition!(ConnectionState::CLOSED,
                                       reason: 'max reconnect attempts exceeded')
            break
          end

          delay = compute_delay
          sleep_with_check(delay)
          break if stopped? || @state_machine.closed?

          begin
            @reconnect_proc.call
            @on_reconnected&.call
            break
          rescue StandardError => e
            Kernel.warn("[kubemq-reconnect] attempt #{@attempt} failed: #{e.message}")
            next
          end
        end
      end

      def compute_delay
        base = [@policy.base_interval * (@policy.multiplier**(@attempt - 1)),
                @policy.max_delay].min
        jitter = base * @policy.jitter_percent * ((rand * 2) - 1)
        [base + jitter, 0.1].max
      end

      def sleep_with_check(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0 || stopped? || @state_machine.closed?

          sleep([remaining, 0.5].min)
        end
      end

      def stopped?
        @mutex.synchronize { @stop_flag }
      end
    end
  end
end
