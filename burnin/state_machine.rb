# frozen_string_literal: true

module KubeMQBurnin
  module WorkerState
    IDLE = 'idle'
    STARTING = 'starting'
    RUNNING = 'running'
    STOPPING = 'stopping'
    STOPPED = 'stopped'
  end

  class StateMachine
    TRANSITIONS = {
      WorkerState::IDLE => [WorkerState::STARTING],
      WorkerState::STARTING => [WorkerState::RUNNING, WorkerState::STOPPED],
      WorkerState::RUNNING => [WorkerState::STOPPING],
      WorkerState::STOPPING => [WorkerState::STOPPED],
      WorkerState::STOPPED => [WorkerState::IDLE]
    }.freeze

    attr_reader :state

    def initialize
      @state = WorkerState::IDLE
      @mutex = Mutex.new
    end

    def transition_to!(new_state)
      @mutex.synchronize do
        allowed = TRANSITIONS.fetch(@state, [])
        unless allowed.include?(new_state)
          raise InvalidTransitionError, "Cannot transition from #{@state} to #{new_state}"
        end

        @state = new_state
      end
    end

    def state_value
      case @state
      when WorkerState::RUNNING then 1
      when WorkerState::STOPPED then 2
      else 0 # IDLE (and any unknown)
      end
    end

    def idle?
      @mutex.synchronize { @state == WorkerState::IDLE }
    end

    def running?
      @mutex.synchronize { @state == WorkerState::RUNNING }
    end

    def can_start?
      @mutex.synchronize { @state == WorkerState::IDLE }
    end

    def can_stop?
      @mutex.synchronize { @state == WorkerState::RUNNING }
    end

    def reset!
      @mutex.synchronize { @state = WorkerState::IDLE }
    end
  end

  class InvalidTransitionError < StandardError; end
end
