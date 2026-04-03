# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'commands.handler'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'cmd-handler')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub = KubeMQ::CQ::CommandsSubscription.new(channel: channel)
  client.subscribe_to_commands(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |cmd|
    puts "Received command: id=#{cmd.id}, metadata=#{cmd.metadata}, body=#{cmd.body}"

    executed = cmd.metadata != 'fail'
    response = KubeMQ::CQ::CommandResponseMessage.new(
      request_id: cmd.id,
      reply_channel: cmd.reply_channel,
      executed: executed,
      error: executed ? nil : 'Simulated failure'
    )
    client.send_response(response)
    puts "Sent response: executed=#{executed}"
  end

  puts "Listening for commands on '#{channel}'. Press Ctrl+C to stop."
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
