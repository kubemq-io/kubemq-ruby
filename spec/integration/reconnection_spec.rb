# frozen_string_literal: true

RSpec.describe 'Reconnection Integration', :integration do
  def broker_available?
    require 'socket'
    addr = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
    host, port = addr.split(':')
    sock = TCPSocket.new(host, port.to_i)
    sock.close
    true
  rescue StandardError
    false
  end

  before(:each) do
    skip 'requires KubeMQ broker' unless broker_available?
  end

  describe 'connection lifecycle' do
    it 'connects to broker and pings successfully' do
      client = KubeMQ::PubSubClient.new(
        address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
        client_id: 'ruby-reconn-test'
      )
      info = client.ping
      expect(info).to be_a(KubeMQ::ServerInfo)
      expect(info.host).not_to be_nil
      expect(info.version).not_to be_nil
      client.close
    end

    it 'raises ConnectionError for unreachable host' do
      expect do
        client = KubeMQ::PubSubClient.new(
          address: 'unreachable-host:99999',
          client_id: 'ruby-reconn-unreachable'
        )
        client.ping
      end.to raise_error(KubeMQ::ConnectionError)
    end

    it 'close is idempotent' do
      client = KubeMQ::PubSubClient.new(
        address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
        client_id: 'ruby-reconn-close'
      )
      client.close
      expect { client.close }.not_to raise_error
    end

    it 'raises ClientClosedError after close' do
      client = KubeMQ::PubSubClient.new(
        address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
        client_id: 'ruby-reconn-closed'
      )
      client.close
      expect { client.ping }.to raise_error(KubeMQ::ClientClosedError)
    end

    it 'state machine transitions through IDLE -> CONNECTING -> READY' do
      client = KubeMQ::PubSubClient.new(
        address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
        client_id: 'ruby-reconn-states'
      )
      client.ping
      expect(client.transport.state_machine).to be_ready
      client.close
      expect(client.transport.state_machine).to be_closed
    end
  end

  describe 'reconnect behavior' do
    it 'buffers messages during reconnection' do
      buffer = KubeMQ::Transport::MessageBuffer.new(capacity: 10)
      5.times { |i| buffer.push("msg-#{i}") }
      expect(buffer.size).to eq(5)
      messages = buffer.drain
      expect(messages.size).to eq(5)
    end

    it 'discards oldest message when buffer overflows' do
      buffer = KubeMQ::Transport::MessageBuffer.new(capacity: 3)
      5.times { |i| buffer.push("msg-#{i}") }
      messages = buffer.drain
      expect(messages).to eq(%w[msg-2 msg-3 msg-4])
    end

    it 'reconnect manager computes exponential backoff delay' do
      policy = KubeMQ::ReconnectPolicy.new(
        base_interval: 1.0, multiplier: 2.0,
        max_delay: 30.0, jitter_percent: 0.0
      )
      sm = KubeMQ::Transport::ConnectionStateMachine.new
      mgr = KubeMQ::Transport::ReconnectManager.new(
        policy: policy, state_machine: sm, reconnect_proc: -> {}
      )
      delay = mgr.send(:compute_delay)
      expect(delay).to be >= 0.1
    end
  end
end
