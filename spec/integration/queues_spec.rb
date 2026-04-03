# frozen_string_literal: true

RSpec.describe 'Queues Integration', :integration do
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

  before(:all) do
    skip 'requires KubeMQ broker' unless broker_available?
    @client = KubeMQ::QueuesClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-integration-queues'
    )
  end

  after(:all) do
    @client&.close
  end

  describe 'Simple API' do
    it 'sends single queue message and receives QueueSendResult' do
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.simple', body: 'simple-msg'
      )
      result = @client.send_queue_message(msg)
      expect(result).to be_a(KubeMQ::Queues::QueueSendResult)
      expect(result).not_to be_error
    end

    it 'sends batch of messages' do
      msgs = (1..3).map do |i|
        KubeMQ::Queues::QueueMessage.new(
          channel: 'integration.q.batch', body: "batch-#{i}"
        )
      end
      results = @client.send_queue_messages_batch(msgs)
      expect(results.size).to eq(3)
      results.each { |r| expect(r).not_to be_error }
    end

    it 'receives messages from queue' do
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.receive', body: 'receive-test'
      )
      @client.send_queue_message(msg)
      sleep(0.5)

      received = @client.receive_queue_messages(
        channel: 'integration.q.receive',
        max_messages: 10,
        wait_timeout_seconds: 3
      )
      expect(received).not_to be_empty
      expect(received.first).to be_a(KubeMQ::Queues::QueueMessageReceived)
    end

    it 'peeks messages without consuming' do
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.peek', body: 'peek-test'
      )
      @client.send_queue_message(msg)
      sleep(0.5)

      peeked = @client.receive_queue_messages(
        channel: 'integration.q.peek',
        max_messages: 10,
        wait_timeout_seconds: 3,
        peek: true
      )
      expect(peeked).not_to be_empty
    end

    it 'acks all messages in queue' do
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.ackall', body: 'ack-test'
      )
      @client.send_queue_message(msg)
      sleep(0.5)

      count = @client.ack_all_queue_messages(channel: 'integration.q.ackall')
      expect(count).to be >= 0
    end
  end

  describe 'Stream API' do
    it 'sends message via upstream sender' do
      sender = @client.create_upstream_sender
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.stream', body: 'stream-msg'
      )
      results = sender.publish([msg])
      expect(results.first).to be_a(KubeMQ::Queues::QueueSendResult)
      sender.close
    end

    it 'polls messages via downstream receiver' do
      msg = KubeMQ::Queues::QueueMessage.new(
        channel: 'integration.q.poll', body: 'poll-msg'
      )
      @client.send_queue_message(msg)
      sleep(0.5)

      receiver = @client.create_downstream_receiver
      req = KubeMQ::Queues::QueuePollRequest.new(
        channel: 'integration.q.poll',
        max_items: 10,
        wait_timeout: 3,
        auto_ack: true
      )
      response = receiver.poll(req)
      expect(response).to be_a(KubeMQ::Queues::QueuePollResponse)
      expect(response.messages).not_to be_empty
      receiver.close
    end

    it 'validates empty channel on poll' do
      expect do
        @client.poll(KubeMQ::Queues::QueuePollRequest.new(channel: ''))
      end.to raise_error(KubeMQ::ValidationError)
    end

    it 'sends batch via stream upstream' do
      sender = @client.create_upstream_sender
      msgs = (1..3).map do |i|
        KubeMQ::Queues::QueueMessage.new(
          channel: 'integration.q.streambatch', body: "b#{i}"
        )
      end
      results = sender.publish(msgs)
      expect(results.size).to eq(3)
      sender.close
    end
  end
end
