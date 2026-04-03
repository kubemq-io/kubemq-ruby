# Events & Events Store

KubeMQ provides two pub/sub patterns: **events** (fire-and-forget) and **events store** (durable with replay). Both are managed through `KubeMQ::PubSubClient`.

## Events (Fire-and-Forget)

Events are delivered in real time to all active subscribers. No persistence — if nobody is listening, the message is lost.

### Sending Events

```ruby
require "kubemq"

client = KubeMQ::PubSubClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "publisher"
)

result = client.send_event(
  KubeMQ::PubSub::EventMessage.new(
    channel: "events.orders",
    metadata: "order-created",
    body: '{"order_id": 42}',
    tags: { "env" => "production", "priority" => "high" }
  )
)
puts "Sent: #{result.id}" if result.sent
client.close
```

### Subscribing to Events

Subscriptions run on a background thread. Pass a block to process each incoming event:

```ruby
token = KubeMQ::CancellationToken.new
sub = KubeMQ::PubSub::EventsSubscription.new(channel: "events.orders")

subscription = client.subscribe_to_events(sub, cancellation_token: token) do |event|
  puts "#{event.channel}: #{event.body}"
end

# Stop the subscription when done
token.cancel
subscription.wait(5)
```

### Wildcard Channels

Events support wildcard subscriptions for flexible topic routing:

| Pattern | Matches |
|---------|---------|
| `events.*` | `events.orders`, `events.users` (one level) |
| `events.>` | `events.orders`, `events.orders.created` (all levels) |

```ruby
sub = KubeMQ::PubSub::EventsSubscription.new(channel: "events.>")
client.subscribe_to_events(sub, cancellation_token: token) do |event|
  puts "Wildcard match on #{event.channel}"
end
```

### Consumer Groups

Distribute messages across multiple subscribers with the `group` parameter. Each message is delivered to exactly one member of the group:

```ruby
sub = KubeMQ::PubSub::EventsSubscription.new(
  channel: "events.orders",
  group: "order-processors"
)
```

### Error Callback

Supply an `on_error` proc to handle stream-level errors without crashing the subscription:

```ruby
client.subscribe_to_events(
  sub,
  cancellation_token: token,
  on_error: ->(err) { logger.error("Subscription error: #{err.message}") }
) { |event| process(event) }
```

## Streaming Event Sender

For high-throughput scenarios, a streaming sender keeps a persistent gRPC stream open and avoids per-message connection overhead:

```ruby
sender = client.create_events_sender

100.times do |i|
  sender.publish(
    KubeMQ::PubSub::EventMessage.new(channel: "events.metrics", body: "value=#{i}")
  )
end

sender.close
```

## Events Store (Durable)

Events store messages are persisted by the broker and can be replayed by new subscribers. Use `send_event_store` and `EventStoreMessage`:

```ruby
result = client.send_event_store(
  KubeMQ::PubSub::EventStoreMessage.new(
    channel: "events_store.orders",
    body: '{"order_id": 99}',
    metadata: "order-created"
  )
)
puts "Stored: #{result.id}" if result.sent
```

## Subscribe to Events Store

Events store subscriptions accept a **start position** that controls replay:

| Position | Constant | Value for `start_position_value` |
|----------|----------|----------------------------------|
| New only | `START_NEW_ONLY` | — |
| From first | `START_FROM_FIRST` | — |
| From last | `START_FROM_LAST` | — |
| At sequence | `START_AT_SEQUENCE` | Sequence number |
| At time | `START_AT_TIME` | Unix timestamp (nanoseconds) |
| Time delta | `START_AT_TIME_DELTA` | Seconds ago |

```ruby
sub = KubeMQ::PubSub::EventsStoreSubscription.new(
  channel: "events_store.orders",
  start_position: KubeMQ::PubSub::EventStoreStartPosition::START_FROM_FIRST
)

client.subscribe_to_events_store(sub, cancellation_token: token) do |event|
  puts "Seq #{event.sequence}: #{event.body}"
end
```

### Replay from a Specific Sequence

```ruby
sub = KubeMQ::PubSub::EventsStoreSubscription.new(
  channel: "events_store.orders",
  start_position: KubeMQ::PubSub::EventStoreStartPosition::START_AT_SEQUENCE,
  start_position_value: 42
)
```

### Replay Last 5 Minutes

```ruby
sub = KubeMQ::PubSub::EventsStoreSubscription.new(
  channel: "events_store.orders",
  start_position: KubeMQ::PubSub::EventStoreStartPosition::START_AT_TIME_DELTA,
  start_position_value: 300
)
```

## Streaming Events Store Sender

Similar to the events sender but with synchronous confirmation per message:

```ruby
sender = client.create_events_store_sender

result = sender.publish(
  KubeMQ::PubSub::EventStoreMessage.new(
    channel: "events_store.audit",
    body: "user-login"
  )
)
puts "Confirmed: #{result.id}" if result.sent

sender.close
```

## Channel Management

```ruby
client.create_events_channel("events.new-topic")
client.create_events_store_channel("events_store.new-topic")

channels = client.list_events_channels
channels.each { |ch| puts "#{ch.name} active=#{ch.active?}" }

client.delete_events_channel("events.old-topic")
client.delete_events_store_channel("events_store.old-topic")
```

## Error Handling

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::ValidationError => e
  warn "Invalid message: #{e.message} — #{e.suggestion}"
rescue KubeMQ::ConnectionError => e
  warn "Broker unreachable: #{e.message}"
  retry if e.retryable?
rescue KubeMQ::ClientClosedError
  warn "Client was closed — create a new one"
end
```

See [Error Handling](error-handling.md) for the full error hierarchy and recovery patterns.
