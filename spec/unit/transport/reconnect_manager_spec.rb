# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::ReconnectManager do
  let(:policy) do
    KubeMQ::ReconnectPolicy.new(
      enabled: true,
      base_interval: 0.05,
      multiplier: 2.0,
      max_delay: 0.2,
      jitter_percent: 0.0,
      max_attempts: 3
    )
  end
  let(:state_machine) { KubeMQ::Transport::ConnectionStateMachine.new }
  let(:reconnect_calls) { [] }
  let(:reconnect_proc) { -> { reconnect_calls << Time.now } }

  subject(:manager) do
    described_class.new(
      policy: policy,
      state_machine: state_machine,
      reconnect_proc: reconnect_proc
    )
  end

  after { manager.stop }

  describe '#start' do
    it 'increments attempt count' do
      manager.start
      sleep(0.3)
      expect(manager.attempt).to be >= 1
    end

    it 'calls reconnect_proc on each attempt' do
      manager.start
      sleep(0.3)
      expect(reconnect_calls).not_to be_empty
    end

    it 'stops when reconnect_proc succeeds' do
      call_count = 0
      mgr = described_class.new(
        policy: policy,
        state_machine: state_machine,
        reconnect_proc: -> { call_count += 1 }
      )
      mgr.start
      sleep(0.5)
      mgr.stop
      expect(call_count).to eq(1)
    end

    it 'retries on reconnect_proc failure' do
      attempts = 0
      mgr = described_class.new(
        policy: policy,
        state_machine: state_machine,
        reconnect_proc: lambda {
          attempts += 1
          raise 'fail' if attempts < 2
        }
      )
      mgr.start
      sleep(0.5)
      mgr.stop
      expect(attempts).to be >= 2
    end
  end

  describe 'max_attempts' do
    it 'transitions to CLOSED when max_attempts exceeded' do
      failing_proc = -> { raise 'connection failed' }
      mgr = described_class.new(
        policy: policy,
        state_machine: state_machine,
        reconnect_proc: failing_proc
      )
      state_machine.transition!(KubeMQ::ConnectionState::CONNECTING)
      state_machine.transition!(KubeMQ::ConnectionState::READY)
      state_machine.transition!(KubeMQ::ConnectionState::RECONNECTING)
      mgr.start
      sleep(1)
      mgr.stop
      expect(state_machine).to be_closed
    end
  end

  describe '#stop' do
    it 'stops the reconnect loop' do
      manager.start
      manager.stop
      count = reconnect_calls.size
      sleep(0.2)
      expect(reconnect_calls.size).to eq(count)
    end

    it 'is idempotent' do
      manager.start
      manager.stop
      expect { manager.stop }.not_to raise_error
    end
  end

  describe 'on_reconnected callback' do
    it 'fires on_reconnected after successful reconnection' do
      reconnected = false
      mgr = described_class.new(
        policy: policy,
        state_machine: state_machine,
        reconnect_proc: -> {},
        on_reconnected: -> { reconnected = true }
      )
      mgr.start
      sleep(0.3)
      mgr.stop
      expect(reconnected).to be true
    end
  end
end
