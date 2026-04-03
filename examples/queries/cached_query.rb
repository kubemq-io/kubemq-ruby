# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queries.cached'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'query-cache-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new
  sub = KubeMQ::CQ::QueriesSubscription.new(channel: channel)
  client.subscribe_to_queries(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |query|
    puts "Handler processing: #{query.metadata}"
    response = KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      executed: true,
      body: 'computed-result',
      metadata: 'cached-response'
    )
    client.send_response(response)
  end
  sleep 1

  msg = KubeMQ::CQ::QueryMessage.new(
    channel: channel,
    timeout: 10,
    metadata: 'get-config',
    body: 'config-key',
    cache_key: 'config:main',
    cache_ttl: 60
  )

  result1 = client.send_query(msg)
  puts "Query 1: executed=#{result1.executed}, cache_hit=#{result1.cache_hit}, body=#{result1.body}"

  result2 = client.send_query(msg)
  puts "Query 2: executed=#{result2.executed}, cache_hit=#{result2.cache_hit}, body=#{result2.body}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
