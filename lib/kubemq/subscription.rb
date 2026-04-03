# frozen_string_literal: true

module KubeMQ
  # Handle for an active subscription running on a background thread.
  #
  # Returned by +subscribe_to_*+ methods on {PubSubClient} and {CQClient}.
  # Use {#cancel} to stop the subscription, {#active?} to check its state,
  # and {#wait} or {#join} to block until the subscription thread exits.
  #
  # @note This class is thread-safe. Status transitions and error state are
  #   protected by a mutex.
  #
  # @example Cancel a subscription gracefully
  #   subscription = client.subscribe_to_events(sub) { |e| process(e) }
  #   # ... later ...
  #   subscription.cancel
  #   subscription.wait(5) # wait up to 5 seconds for thread to exit
  #
  # @see CancellationToken
  # @see PubSubClient#subscribe_to_events
  # @see CQClient#subscribe_to_commands
  class Subscription
    # @!attribute [r] status
    #   @return [Symbol] current subscription state — +:active+, +:cancelled+,
    #     +:error+, or +:closed+
    # @!attribute [r] last_error
    #   @return [StandardError, nil] the most recent error, or +nil+ if none
    attr_reader :status, :last_error

    # Creates a new subscription handle.
    #
    # @api private
    # @param thread [Thread] the background thread running the subscription loop
    # @param cancellation_token [CancellationToken] token used to signal cancellation
    def initialize(thread:, cancellation_token:)
      @thread = thread
      @cancellation_token = cancellation_token
      @status = :active
      @last_error = nil
      @mutex = Mutex.new
    end

    # Cancels the subscription, stops the gRPC stream, and waits up to
    # 5 seconds for the background thread to exit.
    #
    # @return [void]
    def cancel
      @mutex.synchronize { @status = :cancelled }
      @cancellation_token.cancel
      begin; @thread[:grpc_call]&.cancel; rescue StandardError; end
      @thread.join(5)
    end

    # Returns whether the subscription is still actively receiving messages.
    #
    # @return [Boolean] +true+ if status is +:active+ and the thread is alive
    def active?
      @mutex.synchronize { @status == :active } && @thread.alive?
    end

    # Blocks the calling thread until the subscription thread exits or the
    # timeout elapses.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait (+nil+ for indefinite)
    # @return [Thread, nil] the subscription thread if it exited, +nil+ on timeout
    def wait(timeout = nil)
      @thread.join(timeout)
    end

    # Alias for {#wait}. Blocks until the subscription thread exits.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait (+nil+ for indefinite)
    # @return [Thread, nil] the subscription thread if it exited, +nil+ on timeout
    def join(timeout = nil)
      @thread.join(timeout)
    end

    # Records an error on this subscription.
    #
    # @api private
    # @param error [StandardError] the error that occurred
    # @return [void]
    def mark_error(error)
      @mutex.synchronize do
        @status = :error
        @last_error = error
      end
    end

    # Marks this subscription as closed.
    #
    # @api private
    # @return [void]
    def mark_closed
      @mutex.synchronize { @status = :closed }
    end
  end
end
