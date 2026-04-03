# frozen_string_literal: true

module KubeMQ
  module Transport
    # Finite state machine governing the gRPC connection lifecycle.
    #
    # Tracks transitions between {ConnectionState} values and fires registered
    # callbacks on state changes. Invalid transitions raise {Error}.
    #
    # Valid transition graph:
    #   IDLE -> CONNECTING, CLOSED
    #   CONNECTING -> READY, CLOSED, RECONNECTING, IDLE
    #   READY -> RECONNECTING, CLOSED
    #   RECONNECTING -> CONNECTING, READY, CLOSED
    #   CLOSED -> (terminal)
    #
    # @api private
    # @note This class is thread-safe. All state reads and transitions are
    #   mutex-protected.
    #
    # @see GrpcTransport
    # @see ReconnectManager
    # @see ConnectionState
    class ConnectionStateMachine
      # Map of each state to its permitted successor states.
      VALID_TRANSITIONS = {
        ConnectionState::IDLE => [ConnectionState::CONNECTING, ConnectionState::CLOSED],
        ConnectionState::CONNECTING => [ConnectionState::READY, ConnectionState::CLOSED,
                                        ConnectionState::RECONNECTING, ConnectionState::IDLE],
        ConnectionState::READY => [ConnectionState::RECONNECTING, ConnectionState::CLOSED],
        ConnectionState::RECONNECTING => [ConnectionState::CONNECTING, ConnectionState::READY,
                                          ConnectionState::CLOSED],
        ConnectionState::CLOSED => []
      }.freeze

      # @return [Integer] the current {ConnectionState} value
      attr_reader :state

      # Creates a new state machine starting in {ConnectionState::IDLE}.
      def initialize
        @state = ConnectionState::IDLE
        @mutex = Mutex.new
        @callbacks = {
          on_connected: nil,
          on_disconnected: nil,
          on_reconnecting: nil,
          on_error: nil
        }
      end

      # Registers a callback invoked when the connection reaches READY.
      #
      # @yield [server_info] called with the broker's {ServerInfo}
      # @yieldparam server_info [ServerInfo, nil] broker information
      # @return [void]
      def on_connected(&block)
        @mutex.synchronize { @callbacks[:on_connected] = block }
      end

      # Registers a callback invoked when the connection reaches CLOSED.
      #
      # @yield [reason] called with a human-readable close reason
      # @yieldparam reason [String] reason for disconnection
      # @return [void]
      def on_disconnected(&block)
        @mutex.synchronize { @callbacks[:on_disconnected] = block }
      end

      # Registers a callback invoked when the connection enters RECONNECTING.
      #
      # @yield [attempt] called with the current reconnect attempt number
      # @yieldparam attempt [Integer] attempt counter
      # @return [void]
      def on_reconnecting(&block)
        @mutex.synchronize { @callbacks[:on_reconnecting] = block }
      end

      # Registers a callback invoked on invalid state transitions.
      #
      # @yield [error] called with the {Error} describing the invalid transition
      # @yieldparam error [Error] the transition error
      # @return [void]
      def on_error(&block)
        @mutex.synchronize { @callbacks[:on_error] = block }
      end

      # Transitions to a new state, firing the appropriate callback.
      #
      # @param new_state [Integer] the target {ConnectionState} value
      # @param context [Hash] optional context passed to the callback
      #   (+:server_info+, +:attempt+, or +:reason+)
      # @return [void]
      # @raise [Error] if the transition is invalid per {VALID_TRANSITIONS}
      def transition!(new_state, **context)
        callback = nil
        @mutex.synchronize do
          valid = VALID_TRANSITIONS.fetch(@state, [])
          unless valid.include?(new_state)
            error = KubeMQ::Error.new("Invalid state transition from #{@state} to #{new_state}")
            err_cb = @callbacks[:on_error]
            err_cb&.call(error)
            raise error
          end

          old_state = @state
          @state = new_state
          callback = resolve_callback(new_state, old_state, context)
        end
        callback&.call
      end

      # Returns the current state with mutex synchronization.
      #
      # @return [Integer] the current {ConnectionState} value
      def current_state
        @mutex.synchronize { @state }
      end

      # Returns whether the connection is in the READY state.
      #
      # @return [Boolean] +true+ if connected and operational
      def ready?
        current_state == ConnectionState::READY
      end

      # Returns whether the connection has been permanently closed.
      #
      # @return [Boolean] +true+ if in the terminal CLOSED state
      def closed?
        current_state == ConnectionState::CLOSED
      end

      private

      def resolve_callback(new_state, _old_state, context)
        case new_state
        when ConnectionState::READY
          cb = @callbacks[:on_connected]
          cb ? -> { cb.call(context[:server_info]) } : nil
        when ConnectionState::RECONNECTING
          cb = @callbacks[:on_reconnecting]
          cb ? -> { cb.call(context[:attempt] || 0) } : nil
        when ConnectionState::CLOSED
          cb = @callbacks[:on_disconnected]
          cb ? -> { cb.call(context[:reason] || 'closed') } : nil
        end
      end
    end
  end
end
