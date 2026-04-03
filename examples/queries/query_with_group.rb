# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queries.group'
group = 'query-workers'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'query-group-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub1 = KubeMQ::CQ::QueriesSubscription.new(channel: channel, group: group)
  client.subscribe_to_queries(sub1, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |query|
    puts "Worker-1 handling: #{query.metadata}"
    client.send_response(KubeMQ::CQ::QueryResponseMessage.new(
                           request_id: query.id, reply_channel: query.reply_channel, executed: true,
                           body: 'worker-1-result'
                         ))
  end

  sub2 = KubeMQ::CQ::QueriesSubscription.new(channel: channel, group: group)
  client.subscribe_to_queries(sub2, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |query|
    puts "Worker-2 handling: #{query.metadata}"
    client.send_response(KubeMQ::CQ::QueryResponseMessage.new(
                           request_id: query.id, reply_channel: query.reply_channel, executed: true,
                           body: 'worker-2-result'
                         ))
  end
  sleep 1

  3.times do |i|
    msg = KubeMQ::CQ::QueryMessage.new(channel: channel, timeout: 10, metadata: "query-#{i}", body: "data-#{i}")
    result = client.send_query(msg)
    puts "Query #{i}: executed=#{result.executed}, body=#{result.body}"
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
