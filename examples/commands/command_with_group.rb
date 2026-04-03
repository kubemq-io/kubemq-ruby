# frozen_string_literal: true

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'commands.group'
group = 'cmd-workers'

begin
  client = KubeMQ::CQClient.new(address: address, client_id: 'cmd-group-example')
  puts "Connected to #{address}"

  cancel = KubeMQ::CancellationToken.new

  sub1 = KubeMQ::CQ::CommandsSubscription.new(channel: channel, group: group)
  client.subscribe_to_commands(sub1, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |cmd|
    puts "Worker-1 handling: #{cmd.metadata}"
    client.send_response(KubeMQ::CQ::CommandResponseMessage.new(
                           request_id: cmd.id, reply_channel: cmd.reply_channel, executed: true
                         ))
  end

  sub2 = KubeMQ::CQ::CommandsSubscription.new(channel: channel, group: group)
  client.subscribe_to_commands(sub2, cancellation_token: cancel, on_error: lambda { |e|
    puts "Error: #{e.message}"
  }) do |cmd|
    puts "Worker-2 handling: #{cmd.metadata}"
    client.send_response(KubeMQ::CQ::CommandResponseMessage.new(
                           request_id: cmd.id, reply_channel: cmd.reply_channel, executed: true
                         ))
  end
  sleep 1

  3.times do |i|
    msg = KubeMQ::CQ::CommandMessage.new(channel: channel, timeout: 10, metadata: "cmd-#{i}", body: "data-#{i}")
    result = client.send_command(msg)
    puts "Command #{i}: executed=#{result.executed}"
  end
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  cancel&.cancel
  client&.close
  puts 'Done'
end
