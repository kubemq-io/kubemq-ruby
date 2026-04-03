# frozen_string_literal: true

module KubeMQ
  module PubSub
    # Result returned after sending an event via {PubSubClient#send_event}.
    #
    # Check {#sent} to confirm the broker accepted the event. If +sent+ is
    # +false+, inspect {#error} for the reason.
    #
    # @see PubSubClient#send_event
    # @see EventMessage
    class EventSendResult
      # @!attribute [r] id
      #   @return [String] the event identifier echoed back by the broker
      # @!attribute [r] sent
      #   @return [Boolean] +true+ if the broker accepted the event
      # @!attribute [r] error
      #   @return [String, nil] error description if the send failed
      attr_reader :id, :sent, :error

      # @param id [String] event identifier
      # @param sent [Boolean] whether the event was accepted
      # @param error [String, nil] error description on failure
      def initialize(id:, sent:, error: nil)
        @id = id
        @sent = sent
        @error = error
      end
    end
  end
end
