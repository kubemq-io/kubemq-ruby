# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'queries.handler'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'query-handler')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::CQ::QueriesSubscription.new(channel: channel)
  client.subscribe_to_queries(sub, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |query|
    puts "Received query: id=#{query.id}, metadata=#{query.metadata}, body=#{query.body}"

    response = KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      executed: true,
      body: "{\"status\":\"ok\",\"data\":\"result-for-#{query.metadata}\"}",
      metadata: 'application/json'
    )
    client.send_response(response)
    puts 'Sent query response'
  end

  puts "Listening for queries on '#{channel}'. Press Ctrl+C to stop."
  cancel.wait
rescue Interrupt
  puts "\nShutting down..."
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
