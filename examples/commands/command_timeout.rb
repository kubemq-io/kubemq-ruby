# frozen_string_literal: true

# Example: Command Timeout (no handler)
# Expected output:
#   Connected to localhost:50000
#   Sending command with short timeout and no handler...
#   Command timed out (expected): <error message>
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'commands.timeout'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'cmd-timeout-example')
  puts "Connected to #{address}"

  puts 'Sending command with short timeout and no handler...'
  msg = KubeMQ::CQ::CommandMessage.new(
    channel: channel,
    timeout: 2,
    metadata: 'will-timeout',
    body: 'no-handler'
  )

  result = client.send_command(msg)
  if result.error.to_s.empty?
    puts "Command response (unexpected): executed=#{result.executed}"
  else
    puts "Command timed out (expected): #{result.error}"
  end
rescue KubeMQ::Error => e
  puts "Command timed out (expected): #{e.message}"
ensure
  client&.close
  puts 'Done'
end
