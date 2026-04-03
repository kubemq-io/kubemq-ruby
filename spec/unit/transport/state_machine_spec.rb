# frozen_string_literal: true

RSpec.describe KubeMQ::Transport::ConnectionStateMachine do
  subject(:sm) { described_class.new }

  describe 'initial state' do
    it 'starts in IDLE' do
      expect(sm.current_state).to eq(KubeMQ::ConnectionState::IDLE)
    end

    it 'is not ready' do
      expect(sm).not_to be_ready
    end

    it 'is not closed' do
      expect(sm).not_to be_closed
    end
  end

  describe '#transition!' do
    it 'transitions IDLE -> CONNECTING -> READY' do
      sm.transition!(KubeMQ::ConnectionState::CONNECTING)
      expect(sm.current_state).to eq(KubeMQ::ConnectionState::CONNECTING)

      sm.transition!(KubeMQ::ConnectionState::READY)
      expect(sm).to be_ready
    end

    it 'transitions READY -> RECONNECTING' do
      sm.transition!(KubeMQ::ConnectionState::CONNECTING)
      sm.transition!(KubeMQ::ConnectionState::READY)
      sm.transition!(KubeMQ::ConnectionState::RECONNECTING)
      expect(sm.current_state).to eq(KubeMQ::ConnectionState::RECONNECTING)
    end

    it 'transitions READY -> CLOSED' do
      sm.transition!(KubeMQ::ConnectionState::CONNECTING)
      sm.transition!(KubeMQ::ConnectionState::READY)
      sm.transition!(KubeMQ::ConnectionState::CLOSED)
      expect(sm).to be_closed
    end

    it 'raises Error for invalid transition' do
      expect do
        sm.transition!(KubeMQ::ConnectionState::READY)
      end.to raise_error(KubeMQ::Error, /Invalid state transition/)
    end

    it 'disallows transitions from CLOSED' do
      sm.transition!(KubeMQ::ConnectionState::CLOSED)
      expect do
        sm.transition!(KubeMQ::ConnectionState::IDLE)
      end.to raise_error(KubeMQ::Error, /Invalid state transition/)
    end
  end

  describe 'callbacks' do
    it 'fires on_connected callback after transition to READY' do
      server_info = nil
      sm.on_connected { |info| server_info = info }
      sm.transition!(KubeMQ::ConnectionState::CONNECTING)
      sm.transition!(KubeMQ::ConnectionState::READY, server_info: 'test-server')
      expect(server_info).to eq('test-server')
    end

    it 'fires on_reconnecting callback with attempt number' do
      attempt_num = nil
      sm.on_reconnecting { |n| attempt_num = n }
      sm.transition!(KubeMQ::ConnectionState::CONNECTING)
      sm.transition!(KubeMQ::ConnectionState::READY)
      sm.transition!(KubeMQ::ConnectionState::RECONNECTING, attempt: 3)
      expect(attempt_num).to eq(3)
    end

    it 'fires on_disconnected callback when transitioning to CLOSED' do
      reason = nil
      sm.on_disconnected { |r| reason = r }
      sm.transition!(KubeMQ::ConnectionState::CLOSED, reason: 'shutdown')
      expect(reason).to eq('shutdown')
    end

    it 'uses default reason for on_disconnected' do
      reason = nil
      sm.on_disconnected { |r| reason = r }
      sm.transition!(KubeMQ::ConnectionState::CLOSED)
      expect(reason).to eq('closed')
    end

    it 'fires on_error callback on invalid transition' do
      error_received = nil
      sm.on_error { |e| error_received = e }
      expect { sm.transition!(KubeMQ::ConnectionState::READY) }.to raise_error(KubeMQ::Error)
      expect(error_received).to be_a(KubeMQ::Error)
      expect(error_received.message).to include('Invalid state transition')
    end
  end
end
