# frozen_string_literal: true

RSpec.describe KubeMQ::QueuesClient do
  let(:stub_client) { instance_double('Kubemq::Kubemq::Stub') }
  let(:transport) do
    instance_double(
      KubeMQ::Transport::GrpcTransport,
      kubemq_client: stub_client,
      ensure_connected!: nil,
      close: nil,
      closed?: false
    )
  end
  let(:config) do
    KubeMQ::Configuration.new(address: 'localhost:50000', client_id: 'test-client')
  end

  subject(:client) do
    c = described_class.allocate
    c.instance_variable_set(:@config, config)
    c.instance_variable_set(:@transport, transport)
    c.instance_variable_set(:@closed, false)
    c.instance_variable_set(:@mutex, Mutex.new)
    c.instance_variable_set(:@stream_mutex, Mutex.new)
    c.instance_variable_set(:@upstream_sender, nil)
    c.instance_variable_set(:@downstream_receiver, nil)
    c
  end

  describe '.new with transport injection' do
    it 'constructs through initialize with all instance variables set' do
      c = described_class.new(
        address: 'localhost:50000',
        client_id: 'q-init-test',
        transport: transport
      )
      expect(c.config.client_id).to eq('q-init-test')
      expect(c).not_to be_closed
    end
  end

  describe '#send_queue_message_stream stream broken reset' do
    it 'resets upstream_sender on StreamBrokenError' do
      broken_sender = instance_double(KubeMQ::Queues::UpstreamSender)
      allow(broken_sender).to receive(:publish).and_raise(
        KubeMQ::StreamBrokenError.new('stream broken')
      )
      client.instance_variable_set(:@upstream_sender, broken_sender)

      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      expect { client.send_queue_message_stream(msg) }.to raise_error(KubeMQ::StreamBrokenError)
      expect(client.instance_variable_get(:@upstream_sender)).to be_nil
    end
  end

  describe '#poll stream broken reset' do
    it 'resets downstream_receiver on StreamBrokenError' do
      broken_receiver = instance_double(KubeMQ::Queues::DownstreamReceiver)
      allow(broken_receiver).to receive(:poll).and_raise(
        KubeMQ::StreamBrokenError.new('stream broken')
      )
      client.instance_variable_set(:@downstream_receiver, broken_receiver)

      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 1, wait_timeout: 1)
      expect { client.poll(req) }.to raise_error(KubeMQ::StreamBrokenError)
      expect(client.instance_variable_get(:@downstream_receiver)).to be_nil
    end
  end

  describe '#send_queue_message (Simple API)' do
    let(:proto_result) do
      double('QueueResult',
             MessageID: 'qm-1', SentAt: 100,
             ExpirationAt: 0, DelayedTo: 0, IsError: false, Error: '')
    end

    before { allow(stub_client).to receive(:send_queue_message).and_return(proto_result) }

    it 'sends single queue message and returns QueueSendResult' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      result = client.send_queue_message(msg)
      expect(result).to be_a(KubeMQ::Queues::QueueSendResult)
      expect(result.id).to eq('qm-1')
    end

    it 'validates channel' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: '', body: 'data')
      expect { client.send_queue_message(msg) }.to raise_error(KubeMQ::ValidationError)
    end
  end

  describe '#send_queue_messages_batch' do
    let(:batch_result) do
      results = [
        double('R1', MessageID: 'b1', SentAt: 100, ExpirationAt: 0, DelayedTo: 0, IsError: false, Error: ''),
        double('R2', MessageID: 'b2', SentAt: 101, ExpirationAt: 0, DelayedTo: 0, IsError: false, Error: '')
      ]
      double('BatchResponse', Results: results)
    end

    before { allow(stub_client).to receive(:send_queue_messages_batch).and_return(batch_result) }

    it 'sends batch and returns array of QueueSendResult' do
      msgs = [
        KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'd1'),
        KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'd2')
      ]
      results = client.send_queue_messages_batch(msgs)
      expect(results.size).to eq(2)
      expect(results.first.id).to eq('b1')
    end

    it 'raises ValidationError for empty messages array' do
      expect { client.send_queue_messages_batch([]) }
        .to raise_error(KubeMQ::ValidationError, /messages cannot be empty/)
    end

    it 'raises ValidationError for nil messages' do
      expect { client.send_queue_messages_batch(nil) }
        .to raise_error(KubeMQ::ValidationError, /messages cannot be empty/)
    end

    it 'auto-generates batch_id when nil' do
      msgs = [KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'd')]
      expect(stub_client).to receive(:send_queue_messages_batch) do |req|
        expect(req.BatchID).to match(/\A[0-9a-f-]{36}\z/)
        batch_result
      end
      client.send_queue_messages_batch(msgs)
    end

    it 'uses explicit batch_id when provided' do
      msgs = [KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'd')]
      expect(stub_client).to receive(:send_queue_messages_batch) do |req|
        expect(req.BatchID).to eq('my-batch')
        batch_result
      end
      client.send_queue_messages_batch(msgs, batch_id: 'my-batch')
    end
  end

  describe '#receive_queue_messages' do
    let(:proto_response) do
      double('ReceiveResponse',
             IsError: false, Error: '',
             Messages: [])
    end

    before { allow(stub_client).to receive(:receive_queue_messages).and_return(proto_response) }

    it 'returns array of QueueMessageReceived' do
      result = client.receive_queue_messages(channel: 'q.ch')
      expect(result).to eq([])
    end

    it 'validates channel' do
      expect { client.receive_queue_messages(channel: '') }
        .to raise_error(KubeMQ::ValidationError)
    end

    it 'validates max_messages > 1024' do
      expect { client.receive_queue_messages(channel: 'ch', max_messages: 1025) }
        .to raise_error(KubeMQ::ValidationError)
    end

    it 'validates wait_timeout_seconds > 3600' do
      expect { client.receive_queue_messages(channel: 'ch', wait_timeout_seconds: 3601) }
        .to raise_error(KubeMQ::ValidationError)
    end

    it 'raises MessageError on server error' do
      err_resp = double('ReceiveResponse', IsError: true, Error: 'queue error', Messages: nil)
      allow(stub_client).to receive(:receive_queue_messages).and_return(err_resp)
      expect { client.receive_queue_messages(channel: 'q.ch') }
        .to raise_error(KubeMQ::MessageError)
    end
  end

  describe '#ack_all_queue_messages' do
    let(:proto_response) do
      double('AckAllResponse', IsError: false, Error: '', AffectedMessages: 5)
    end

    before { allow(stub_client).to receive(:ack_all_queue_messages).and_return(proto_response) }

    it 'returns count of affected messages' do
      count = client.ack_all_queue_messages(channel: 'q.ch')
      expect(count).to eq(5)
    end
  end

  describe '#create_upstream_sender' do
    it 'returns an UpstreamSender' do
      allow(stub_client).to receive(:queues_upstream) { [].each }
      sender = client.create_upstream_sender
      expect(sender).to be_a(KubeMQ::Queues::UpstreamSender)
      sender.close
    end
  end

  describe '#create_downstream_receiver' do
    it 'returns a DownstreamReceiver' do
      allow(stub_client).to receive(:queues_downstream) { [].each }
      receiver = client.create_downstream_receiver
      expect(receiver).to be_a(KubeMQ::Queues::DownstreamReceiver)
      receiver.close
    end
  end

  describe '#send_queue_message_stream' do
    before do
      allow(stub_client).to receive(:queues_upstream) { [].each }
    end

    it 'validates channel' do
      msg = KubeMQ::Queues::QueueMessage.new(channel: '', body: 'data')
      expect { client.send_queue_message_stream(msg) }.to raise_error(KubeMQ::ValidationError)
    end

    it 'creates upstream sender lazily and sends' do
      allow(stub_client).to receive(:queues_upstream) do |input_enum|
        Enumerator.new do |y|
          input_enum.each do |proto_req|
            result = double('QueueResult',
                            MessageID: 'qm-s1', SentAt: 100,
                            ExpirationAt: 0, DelayedTo: 0,
                            IsError: false, Error: '')
            y.yield(double('Response',
                           RefRequestID: proto_req.RequestID,
                           IsError: false, Error: '',
                           Results: [result]))
          end
        end
      end
      msg = KubeMQ::Queues::QueueMessage.new(channel: 'q.ch', body: 'data')
      result = client.send_queue_message_stream(msg)
      expect(result).to be_a(KubeMQ::Queues::QueueSendResult)
    end
  end

  describe '#poll' do
    before do
      allow(stub_client).to receive(:queues_downstream) { [].each }
    end

    it 'creates downstream receiver lazily' do
      req = KubeMQ::Queues::QueuePollRequest.new(channel: 'q.ch', max_items: 1, wait_timeout: 1)
      expect { client.poll(req) }.to raise_error(KubeMQ::TimeoutError)
    end
  end

  describe '#ack_all_queue_messages error path' do
    it 'raises MessageError on server error' do
      err_resp = double('AckAllResponse', IsError: true, Error: 'ack error', AffectedMessages: 0)
      allow(stub_client).to receive(:ack_all_queue_messages).and_return(err_resp)
      expect { client.ack_all_queue_messages(channel: 'q.ch') }
        .to raise_error(KubeMQ::MessageError, /ack error/)
    end
  end

  describe '#receive_queue_messages with messages' do
    it 'converts proto messages to QueueMessageReceived' do
      attrs = double('Attributes',
                     Timestamp: 100, Sequence: 1, MD5OfBody: 'md5',
                     ReceiveCount: 1, ReRouted: false,
                     ReRoutedFromQueue: '', ExpirationAt: 0, DelayedTo: 0)
      proto_msg = double('QueueMessage',
                         MessageID: 'qm-1', Channel: 'q.ch',
                         Metadata: 'meta', Body: 'body',
                         Tags: { 'k' => 'v' }.to_a.to_h,
                         Attributes: attrs,
                         Policy: nil)
      allow(proto_msg).to receive_message_chain(:Tags, :to_h).and_return({ 'k' => 'v' })

      response = double('ReceiveResponse', IsError: false, Error: '', Messages: [proto_msg])
      allow(stub_client).to receive(:receive_queue_messages).and_return(response)

      allow(KubeMQ::Transport::Converter).to receive(:proto_to_queue_message_received)
        .and_return({
                      id: 'qm-1', channel: 'q.ch', metadata: 'meta',
                      body: 'body', tags: { 'k' => 'v' },
                      attributes: { timestamp: 100, sequence: 1 }
                    })

      result = client.receive_queue_messages(channel: 'q.ch')
      expect(result.size).to eq(1)
      expect(result.first).to be_a(KubeMQ::Queues::QueueMessageReceived)
      expect(result.first.id).to eq('qm-1')
    end
  end

  describe '#close with active streams' do
    it 'closes upstream sender and downstream receiver' do
      upstream = instance_double(KubeMQ::Queues::UpstreamSender, close: nil)
      downstream = instance_double(KubeMQ::Queues::DownstreamReceiver, close: nil)
      client.instance_variable_set(:@upstream_sender, upstream)
      client.instance_variable_set(:@downstream_receiver, downstream)

      expect(upstream).to receive(:close)
      expect(downstream).to receive(:close)
      client.close
    end
  end

  describe 'channel management' do
    before do
      allow(KubeMQ::Transport::ChannelManager).to receive(:create_channel).and_return(true)
      allow(KubeMQ::Transport::ChannelManager).to receive(:delete_channel).and_return(true)
      allow(KubeMQ::Transport::ChannelManager).to receive(:list_channels).and_return([])
    end

    it '#create_queues_channel uses QUEUES type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:create_channel)
        .with(transport, 'test-client', 'q-ch', KubeMQ::ChannelType::QUEUES)
      client.create_queues_channel(channel_name: 'q-ch')
    end

    it '#delete_queues_channel uses QUEUES type' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:delete_channel)
        .with(transport, 'test-client', 'q-ch', KubeMQ::ChannelType::QUEUES)
      client.delete_queues_channel(channel_name: 'q-ch')
    end

    it '#list_queues_channels delegates correctly' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::QUEUES, nil)
      client.list_queues_channels
    end

    it '#list_queues_channels passes search' do
      expect(KubeMQ::Transport::ChannelManager).to receive(:list_channels)
        .with(transport, 'test-client', KubeMQ::ChannelType::QUEUES, 'test')
      client.list_queues_channels(search: 'test')
    end
  end
end
