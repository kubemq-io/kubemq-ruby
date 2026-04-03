# frozen_string_literal: true

# Example: Send a Command and Handle the Response (RPC)
# Expected output:
#   Connected to localhost:50000
#   Handler received command: restart-service
#   Command result: executed=true, error=
#   Done

require 'kubemq'

# Step 1: Configure the broker address and channel name
address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'commands.example'

begin
  # Step 2: Create a CQClient connected to the broker
  client = KubeMQ::CQClient.new(address: address, client_id: 'cmd-sender')
  puts "Connected to #{address}"

  # Step 3: Subscribe to commands and set up a handler that responds
  cancel = KubeMQ::CancellationToken.new
  sub = KubeMQ::CQ::CommandsSubscription.new(channel: channel)
  client.subscribe_to_commands(sub, cancellation_token: cancel, on_error: ->(e) { puts "Error: #{e.message}" }) do |cmd|
    puts "Handler received command: #{cmd.metadata}"
    response = KubeMQ::CQ::CommandResponseMessage.new(
      request_id: cmd.id,
      reply_channel: cmd.reply_channel,
      executed: true
    )
    client.send_response(response)
  end
  sleep 1

  # Step 4: Send a command with a 10ms timeout and print the result
  msg = KubeMQ::CQ::CommandMessage.new(
    channel: channel,
    timeout: 10,
    metadata: 'restart-service',
    body: 'service-name'
  )
  result = client.send_command(msg)
  puts "Command result: executed=#{result.executed}, error=#{result.error}"
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  # Step 5: Cancel the subscription and close the client
  cancel&.cancel
  client&.close
  puts 'Done'
end
