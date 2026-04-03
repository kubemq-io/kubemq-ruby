# frozen_string_literal: true

RSpec.describe 'CQ Integration', :integration do
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
    @client = KubeMQ::CQClient.new(
      address: ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000'),
      client_id: 'ruby-integration-cq'
    )
  end

  after(:all) do
    @client&.close
  end

  describe 'Commands' do
    it 'subscribes to commands and receives CommandReceived' do
      received_commands = []
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::CQ::CommandsSubscription.new(channel: 'integration.cmd.sub')

      thread = @client.subscribe_to_commands(sub, cancellation_token: token) do |cmd|
        received_commands << cmd
        resp = KubeMQ::CQ::CommandResponseMessage.new(
          request_id: cmd.id,
          reply_channel: cmd.reply_channel,
          executed: true
        )
        @client.send_response(resp)
      end

      sleep(0.5)
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'integration.cmd.sub', timeout: 5000, body: 'cmd-data'
      )
      result = @client.send_command(msg)
      expect(result).to be_a(KubeMQ::CQ::CommandResponse)
      expect(result.executed).to be true

      token.cancel
      thread.join(3)
    end

    it 'validates timeout is positive' do
      msg = KubeMQ::CQ::CommandMessage.new(
        channel: 'integration.cmd.timeout', timeout: 0, body: 'b'
      )
      expect { @client.send_command(msg) }
        .to raise_error(KubeMQ::ValidationError)
    end

    it 'validates channel is not empty' do
      msg = KubeMQ::CQ::CommandMessage.new(channel: '', timeout: 5000, body: 'b')
      expect { @client.send_command(msg) }
        .to raise_error(KubeMQ::ValidationError)
    end
  end

  describe 'Queries' do
    it 'subscribes to queries and receives QueryReceived' do
      received_queries = []
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'integration.qry.sub')

      thread = @client.subscribe_to_queries(sub, cancellation_token: token) do |qry|
        received_queries << qry
        resp = KubeMQ::CQ::QueryResponseMessage.new(
          request_id: qry.id,
          reply_channel: qry.reply_channel,
          executed: true,
          body: 'query-result',
          metadata: 'ok'
        )
        @client.send_response(resp)
      end

      sleep(0.5)
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'integration.qry.sub', timeout: 5000, body: 'query-data'
      )
      result = @client.send_query(msg)
      expect(result).to be_a(KubeMQ::CQ::QueryResponse)
      expect(result.executed).to be true
      expect(result.body).to eq('query-result')

      token.cancel
      thread.join(3)
    end

    it 'validates cache_ttl when cache_key set' do
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'integration.qry.cache', timeout: 5000,
        body: 'q', cache_key: 'ck', cache_ttl: 0
      )
      expect { @client.send_query(msg) }
        .to raise_error(KubeMQ::ValidationError, /cache_ttl/)
    end

    it 'sends query response with body and metadata' do
      token = KubeMQ::CancellationToken.new
      sub = KubeMQ::CQ::QueriesSubscription.new(channel: 'integration.qry.resp')

      thread = @client.subscribe_to_queries(sub, cancellation_token: token) do |qry|
        resp = KubeMQ::CQ::QueryResponseMessage.new(
          request_id: qry.id,
          reply_channel: qry.reply_channel,
          executed: true,
          body: 'response-body',
          metadata: 'response-meta',
          tags: { 'result_tag' => 'value' }
        )
        @client.send_response(resp)
      end

      sleep(0.5)
      msg = KubeMQ::CQ::QueryMessage.new(
        channel: 'integration.qry.resp', timeout: 5000, body: 'q'
      )
      result = @client.send_query(msg)
      expect(result.executed).to be true

      token.cancel
      thread.join(3)
    end

    it 'validates response request_id' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: '', reply_channel: 'ch', executed: true
      )
      expect { @client.send_response(resp) }
        .to raise_error(KubeMQ::ValidationError, /request_id/)
    end

    it 'validates response reply_channel' do
      resp = KubeMQ::CQ::CommandResponseMessage.new(
        request_id: 'r1', reply_channel: '', executed: true
      )
      expect { @client.send_response(resp) }
        .to raise_error(KubeMQ::ValidationError, /reply_channel/)
    end
  end
end
