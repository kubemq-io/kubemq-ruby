# frozen_string_literal: true

module KubeMQ
  # Thread-safe cooperative cancellation token for stopping subscriptions.
  #
  # Create a token, pass it to a +subscribe_to_*+ method, and call {#cancel}
  # to gracefully stop the subscription. Multiple threads may safely check
  # {#cancelled?} or {#wait} concurrently.
  #
  # @note This class is thread-safe. All state access is synchronized via
  #   a +Mutex+ and +ConditionVariable+.
  #
  # @example Cancel a subscription after 10 seconds
  #   token = KubeMQ::CancellationToken.new
  #   subscription = client.subscribe_to_events(sub, cancellation_token: token) do |event|
  #     process(event)
  #   end
  #   sleep 10
  #   token.cancel
  #   subscription.wait(5)
  #
  # @see Subscription
  class CancellationToken
    # Creates a new uncancelled token.
    def initialize
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @cancelled = false
    end

    # Signals cancellation and wakes all threads waiting on this token.
    #
    # This method is idempotent — calling it multiple times is safe.
    #
    # @return [void]
    def cancel
      @mutex.synchronize do
        @cancelled = true
        @condition.broadcast
      end
    end

    # Returns whether cancellation has been signalled.
    #
    # @return [Boolean] +true+ if {#cancel} has been called
    def cancelled?
      @mutex.synchronize { @cancelled }
    end

    # Blocks the calling thread until the token is cancelled or the timeout elapses.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait (+nil+ for indefinite)
    # @return [Boolean] +true+ if cancelled, +false+ if timed out
    def wait(timeout: nil)
      @mutex.synchronize do
        return true if @cancelled

        @condition.wait(@mutex, timeout)
        @cancelled
      end
    end
  end
end
