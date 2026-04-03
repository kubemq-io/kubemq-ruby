# frozen_string_literal: true

# Example: Send a Query and Receive a Response (RPC with data)
# Expected output:
#   Connected to localhost:50000
#   Handler received query: get-user
#   Query result: executed=true, body=answer-to-get-user, cache_hit=false
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queries.example'

begin
  # Step 2: Create a CQClient connected to the broker
  client = KubeMQ::CQClient.new(address: address, client_id: 'query-sender')
  puts "Connected to #{address}"

  # Step 3: Subscribe to queries and set up a handler that returns data
  cancel = KubeMQ::CancellationToken.new
  sub = KubeMQ::CQ::QueriesSubscription.new(channel: channel)
  client.subscribe_to_queries(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |query|
    puts "Handler received query: #{query.metadata}"
    response = KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      executed: true,
      body: "answer-to-#{query.metadata}",
      metadata: 'result'
    )
    client.send_response(response)
  end
  sleep 1

  # Step 4: Send a query with a 10ms timeout and print the response
  msg = KubeMQ::CQ::QueryMessage.new(
    channel: channel,
    timeout: 10,
    metadata: 'get-user',
    body: 'user-id-42'
  )
  result = client.send_query(msg)
  puts "Query result: executed=#{result.executed}, body=#{result.body}, cache_hit=#{result.cache_hit}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 5: Cancel the subscription and close the client
  cancel&.cancel
  client&.close
  puts 'Done'
end
