# frozen_string_literal: true

module KubeMQ
  module Transport
    # Thread-safe bounded buffer for queuing messages during reconnection.
    #
    # When the transport is disconnected, outbound messages are buffered here.
    # If the buffer reaches capacity, the oldest message is dropped to make
    # room -- consistent with other KubeMQ SDKs.
    #
    # @api private
    # @note This class is thread-safe. All operations are mutex-protected.
    #
    # @see GrpcTransport
    # @see ReconnectManager
    class MessageBuffer
      # Default buffer capacity.
      DEFAULT_CAPACITY = 1000

      # @return [Integer] maximum number of messages this buffer can hold
      attr_reader :capacity

      # @param capacity [Integer] maximum buffer size (default: {DEFAULT_CAPACITY})
      def initialize(capacity: DEFAULT_CAPACITY)
        @capacity = capacity
        @queue = Thread::SizedQueue.new(capacity)
        @mutex = Mutex.new
      end

      # Adds a message to the buffer. If full, the oldest message is dropped.
      #
      # @param message [Object] the message to buffer
      # @return [void]
      def push(message)
        @mutex.synchronize do
          begin
            @queue.pop(true) if @queue.size >= @capacity
          rescue ThreadError
            # queue was emptied concurrently
          end
          begin
            @queue.push(message, true)
          rescue ThreadError
            # queue full; discard
          end
        end
      end

      # Drains all buffered messages. If a block is given, yields each message;
      # otherwise returns them as an array via {#to_a}.
      #
      # @yield [message] each buffered message in FIFO order
      # @yieldparam message [Object] a buffered message
      # @return [Array, nil] array of messages if no block given; +nil+ otherwise
      def drain(&block)
        return to_a unless block

        loop do
          msg = @queue.pop(true)
          block.call(msg)
        rescue ThreadError
          break
        end
      end

      # Drains all messages and returns them as an array.
      #
      # @return [Array<Object>] all buffered messages in FIFO order
      def to_a
        messages = []
        drain { |m| messages << m }
        messages
      end

      # Returns the current number of buffered messages.
      #
      # @return [Integer] number of messages in the buffer
      def size
        @queue.size
      end

      # Returns whether the buffer is empty.
      #
      # @return [Boolean] +true+ if no messages are buffered
      def empty?
        @queue.empty?
      end

      # Returns whether the buffer has reached capacity.
      #
      # @return [Boolean] +true+ if {#size} >= {#capacity}
      def full?
        @queue.size >= @capacity
      end

      # Removes all messages from the buffer.
      #
      # @return [nil]
      def clear
        drain
        nil
      end
    end
  end
end
