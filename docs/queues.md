# Queues

KubeMQ queues provide guaranteed, exactly-once message delivery with transactional acknowledgement. The Ruby SDK offers two APIs:

| API | Transport | Best For |
|-----|-----------|----------|
| **Stream** (recommended) | Bidirectional gRPC stream | High throughput, transactional ack/nack/requeue |
| **Simple** | Unary gRPC calls | Low volume, simple send/receive |

## Stream API (Recommended)

### Sending Messages

Create a persistent upstream sender for efficient batched delivery:

```ruby
require "kubemq"

client = KubeMQ::QueuesClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "queue-producer"
)

sender = client.create_upstream_sender

10.times do |i|
  sender.publish(
    KubeMQ::Queues::QueueMessage.new(
      channel: "queues.tasks",
      body: "{\"task_id\": #{i}}",
      metadata: "batch-job"
    )
  )
end

sender.close
client.close
```

The convenience method `send_queue_message_stream` auto-creates an upstream sender on first call:

```ruby
client.send_queue_message_stream(
  KubeMQ::Queues::QueueMessage.new(channel: "queues.tasks", body: "quick-send")
)
```

### Receiving Messages (Poll)

Poll for messages with transactional acknowledgement:

```ruby
client = KubeMQ::QueuesClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "queue-consumer"
)

request = KubeMQ::Queues::QueuePollRequest.new(
  channel: "queues.tasks",
  max_items: 10,
  wait_timeout: 5,
  auto_ack: false
)

response = client.poll(request)

unless response.error?
  response.messages.each do |msg|
    puts "Processing: #{msg.body}"
    msg.ack
  end
end

client.close
```

### Transaction Actions

#### Per-Message Actions

Each `QueueMessageReceived` supports individual transaction control:

| Method | Description |
|--------|-------------|
| `msg.ack` | Acknowledge — remove from queue |
| `msg.reject` | Negative-acknowledge — redeliver or dead-letter |
| `msg.requeue(channel: "other.queue")` | Move to a different queue |

```ruby
response.messages.each do |msg|
  begin
    process(msg.body)
    msg.ack
  rescue StandardError => e
    msg.reject
  end
end
```

#### Batch Actions

`QueuePollResponse` provides batch operations for the entire poll transaction:

| Method | Description |
|--------|-------------|
| `response.ack_all` | Acknowledge all messages |
| `response.nack_all` | Negative-acknowledge all messages |
| `response.requeue_all(channel:)` | Requeue all to another channel |
| `response.ack_range(sequence_range:)` | Ack specific sequences |
| `response.nack_range(sequence_range:)` | Nack specific sequences |
| `response.requeue_range(channel:, sequence_range:)` | Requeue specific sequences |

```ruby
response = client.poll(request)
unless response.error?
  response.messages.each { |msg| process(msg.body) }
  response.ack_all
end
```

### Downstream Receiver

For advanced control, create a dedicated downstream receiver:

```ruby
receiver = client.create_downstream_receiver

request = KubeMQ::Queues::QueuePollRequest.new(
  channel: "queues.tasks",
  max_items: 5,
  wait_timeout: 10
)

response = receiver.poll(request)
response.messages.each do |msg|
  process(msg.body)
  msg.ack
end

receiver.close
```

## Simple API

For low-volume use cases, the simple API uses unary (non-streaming) gRPC calls:

### Send a Single Message

```ruby
result = client.send_queue_message(
  KubeMQ::Queues::QueueMessage.new(
    channel: "queues.orders",
    body: '{"order_id": 1}'
  )
)
puts "Sent at #{result.sent_at}" unless result.error?
```

### Receive Messages

```ruby
messages = client.receive_queue_messages(
  channel: "queues.orders",
  max_messages: 5,
  wait_timeout_seconds: 10
)
messages.each { |msg| puts msg.body }
```

### Send a Batch

```ruby
messages = 5.times.map do |i|
  KubeMQ::Queues::QueueMessage.new(
    channel: "queues.orders",
    body: "{\"order_id\": #{i}}"
  )
end

results = client.send_queue_messages_batch(messages, batch_id: "batch-001")
results.each { |r| puts "#{r.id}: error=#{r.error?}" }
```

### Acknowledge All

```ruby
count = client.ack_all_queue_messages(channel: "queues.orders")
puts "Acknowledged #{count} messages"
```

## Message Policies

Attach a `QueueMessagePolicy` to control delivery behavior:

```ruby
msg = KubeMQ::Queues::QueueMessage.new(
  channel: "queues.tasks",
  body: "time-sensitive-work",
  policy: KubeMQ::Queues::QueueMessagePolicy.new(
    expiration_seconds: 3600,
    delay_seconds: 30,
    max_receive_count: 3,
    max_receive_queue: "queues.tasks.dlq"
  )
)
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `expiration_seconds` | `Integer` | `0` (never) | Message TTL in seconds |
| `delay_seconds` | `Integer` | `0` | Delay before message becomes visible |
| `max_receive_count` | `Integer` | `0` (unlimited) | Max delivery attempts before dead-lettering |
| `max_receive_queue` | `String` | `""` | Dead-letter queue channel name |

## Real-World Scenario: Task Queue with Dead Letter

```ruby
require "kubemq"

client = KubeMQ::QueuesClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "task-worker"
)

client.send_queue_message(
  KubeMQ::Queues::QueueMessage.new(
    channel: "queues.tasks",
    body: '{"task": "resize-image", "url": "https://example.com/photo.jpg"}',
    policy: KubeMQ::Queues::QueueMessagePolicy.new(
      expiration_seconds: 300,
      max_receive_count: 3,
      max_receive_queue: "queues.tasks.dlq"
    )
  )
)

loop do
  response = client.poll(
    KubeMQ::Queues::QueuePollRequest.new(
      channel: "queues.tasks",
      max_items: 5,
      wait_timeout: 10
    )
  )

  next if response.error?

  response.messages.each do |msg|
    begin
      process_task(msg.body)
      msg.ack
    rescue StandardError => e
      warn "Task failed: #{e.message}"
      msg.reject
    end
  end
end
```

Messages that fail 3 times are automatically routed to `queues.tasks.dlq` for manual inspection.

## Channel Management

```ruby
client.create_queues_channel("queues.new-queue")

channels = client.list_queues_channels
channels.each { |ch| puts ch.name }

client.purge_queue_channel(channel_name: "queues.old-queue")
client.delete_queues_channel("queues.old-queue")
```

## Error Handling

Queue streams can break due to network issues. Handle `StreamBrokenError` by recreating the sender or receiver:

```ruby
begin
  sender.publish(msg)
rescue KubeMQ::StreamBrokenError => e
  warn "Stream broken — #{e.unacked_message_ids.size} unacked messages"
  sender = client.create_upstream_sender
  retry
rescue KubeMQ::TransactionError => e
  warn "Transaction failed: #{e.message}"
end
```

See [Error Handling](error-handling.md) for the full error hierarchy and recovery patterns.
