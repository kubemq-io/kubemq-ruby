# frozen_string_literal: true

# Example: Work Queue Pattern (competing consumers)
# Expected output:
#   Connected to localhost:50000
#   Enqueued 6 tasks
#   Worker-1 processed: task-0
#   Worker-1 processed: task-1
#   Worker-1 processed: task-2
#   Worker-2 processed: task-3
#   Worker-2 processed: task-4
#   Worker-2 processed: task-5
#   Done

require 'kubemq'

address = ENV.fetch('KUBEMQ_ADDRESS', 'localhost:50000')
channel = 'patterns.work_queue'

begin
  client = KubeMQ::QueuesClient.new(address: address, client_id: 'work-queue-example')
  puts "Connected to #{address}"

  # Enqueue tasks
  6.times do |i|
    msg = KubeMQ::Queues::QueueMessage.new(channel: channel, metadata: "task-#{i}", body: "data-#{i}")
    client.send_queue_message(msg)
  end
  puts 'Enqueued 6 tasks'

  # Worker 1 pulls a batch
  msgs1 = client.receive_queue_messages(channel: channel, max_messages: 3, wait_timeout_seconds: 5)
  msgs1.each { |m| puts "Worker-1 processed: #{m.metadata}" }

  # Worker 2 pulls remaining
  msgs2 = client.receive_queue_messages(channel: channel, max_messages: 3, wait_timeout_seconds: 5)
  msgs2.each { |m| puts "Worker-2 processed: #{m.metadata}" }
rescue KubeMQ::Error => e
  puts "KubeMQ error: #{e.message}"
ensure
  client&.close
  puts 'Done'
end
