# frozen_string_literal: true

# Example: Request/Reply Pattern (RPC via queries)
# Expected output:
#   Connected to localhost:50000
#   Handler received query: get-user
#   Reply: answer-to-get-user
#   Handler received query: get-settings
#   Reply: answer-to-get-settings
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'patterns.request_reply'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'rpc-pattern-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  # Server: subscribe and respond to queries
  sub = KubeMQ::CQ::QueriesSubscription.new(channel: channel)
  client.subscribe_to_queries(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |query|
    puts "Handler received query: #{query.metadata}"
    response = KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      executed: true,
      body: "answer-to-#{query.metadata}"
    )
    client.send_response(response)
  end
  sleep 1

  # Client: send queries and read replies
  %w[get-user get-settings].each do |action|
    msg = KubeMQ::CQ::QueryMessage.new(channel: channel, timeout: 10, metadata: action, body: 'request')
    result = client.send_query(msg)
    puts "Reply: #{result.body}"
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
