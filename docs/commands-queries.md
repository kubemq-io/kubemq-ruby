# Commands & Queries

KubeMQ commands and queries implement the request/response (RPC) pattern over gRPC. Both are managed through `KubeMQ::CQClient`.

| Pattern | Semantics | Response Data |
|---------|-----------|---------------|
| **Command** | Fire-and-confirm — did it execute? | `executed` (Boolean), `error` |
| **Query** | Request/response — return data | `body`, `metadata`, `cache_hit` |

> **Timeout convention:** Command and query `timeout` values are in **milliseconds** (proto-aligned). This differs from queue `wait_timeout` which uses seconds.

## Commands (Fire-and-Confirm)

### Sending a Command

```ruby
require "kubemq"

client = KubeMQ::CQClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "command-sender"
)

response = client.send_command(
  KubeMQ::CQ::CommandMessage.new(
    channel: "commands.users",
    metadata: "delete-user",
    body: '{"user_id": 42}',
    timeout: 10_000,
    tags: { "source" => "admin-panel" }
  )
)

if response.executed
  puts "Command executed successfully"
else
  warn "Command failed: #{response.error}"
end

client.close
```

### Handling Commands (Responder)

Subscribe to a channel and respond to incoming commands:

```ruby
token = KubeMQ::CancellationToken.new

client.subscribe_to_commands(
  KubeMQ::CQ::CommandsSubscription.new(channel: "commands.users"),
  cancellation_token: token
) do |cmd|
  puts "Received command: #{cmd.metadata} — #{cmd.body}"

  client.send_response(
    KubeMQ::CQ::CommandResponseMessage.new(
      request_id: cmd.id,
      reply_channel: cmd.reply_channel,
      executed: true
    )
  )
end

sleep
token.cancel
client.close
```

## Queries (Request/Response with Data)

### Sending a Query

```ruby
response = client.send_query(
  KubeMQ::CQ::QueryMessage.new(
    channel: "queries.users",
    metadata: "get-user",
    body: '{"user_id": 42}',
    timeout: 10_000
  )
)

puts "User data: #{response.body}"
puts "Cache hit: #{response.cache_hit}"
```

### Query with Cache

Queries support broker-side caching with `cache_key` and `cache_ttl`:

```ruby
response = client.send_query(
  KubeMQ::CQ::QueryMessage.new(
    channel: "queries.products",
    metadata: "get-product",
    body: '{"sku": "WIDGET-100"}',
    timeout: 10_000,
    cache_key: "product:WIDGET-100",
    cache_ttl: 60_000
  )
)

if response.cache_hit
  puts "Served from cache: #{response.body}"
else
  puts "Fresh response: #{response.body}"
end
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `cache_key` | `String` | Cache key for this query (omit to skip caching) |
| `cache_ttl` | `Integer` | Cache TTL in milliseconds |

### Handling Queries (Responder)

```ruby
client.subscribe_to_queries(
  KubeMQ::CQ::QueriesSubscription.new(channel: "queries.users"),
  cancellation_token: token
) do |query|
  user = find_user(query.body)

  client.send_response(
    KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      body: user.to_json,
      executed: true,
      cache_hit: false
    )
  )
end
```

## Building a Full Responder Service

A production responder typically handles both commands and queries on a long-running process:

```ruby
require "kubemq"

client = KubeMQ::CQClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "user-service"
)

token = KubeMQ::CancellationToken.new
error_handler = ->(err) { warn "Subscription error: #{err.message}" }

client.subscribe_to_commands(
  KubeMQ::CQ::CommandsSubscription.new(channel: "commands.users"),
  cancellation_token: token,
  on_error: error_handler
) do |cmd|
  success = execute_command(cmd.metadata, cmd.body)
  client.send_response(
    KubeMQ::CQ::CommandResponseMessage.new(
      request_id: cmd.id,
      reply_channel: cmd.reply_channel,
      executed: success
    )
  )
end

client.subscribe_to_queries(
  KubeMQ::CQ::QueriesSubscription.new(channel: "queries.users"),
  cancellation_token: token,
  on_error: error_handler
) do |query|
  result = handle_query(query.metadata, query.body)
  client.send_response(
    KubeMQ::CQ::QueryResponseMessage.new(
      request_id: query.id,
      reply_channel: query.reply_channel,
      body: result.to_json,
      executed: true
    )
  )
end

trap("INT") { token.cancel }
sleep
client.close
```

## Timeout Convention

| API | Field | Unit |
|-----|-------|------|
| Commands | `CommandMessage#timeout` | Milliseconds |
| Queries | `QueryMessage#timeout` | Milliseconds |
| Queues | `QueuePollRequest#wait_timeout` | Seconds |
| Queues (simple) | `receive_queue_messages(wait_timeout_seconds:)` | Seconds |

## CQRS Scenario: Order System

Separate writes (commands) from reads (queries) with caching:

```ruby
require "kubemq"

client = KubeMQ::CQClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "order-gateway"
)

response = client.send_command(
  KubeMQ::CQ::CommandMessage.new(
    channel: "commands.orders",
    metadata: "create-order",
    body: '{"product": "Widget", "qty": 5}',
    timeout: 10_000
  )
)
puts "Order created" if response.executed

response = client.send_query(
  KubeMQ::CQ::QueryMessage.new(
    channel: "queries.orders",
    metadata: "get-order",
    body: '{"order_id": 1}',
    timeout: 10_000,
    cache_key: "order:1",
    cache_ttl: 30_000
  )
)
puts "Order: #{response.body} (cached=#{response.cache_hit})"

client.close
```

## Channel Management

```ruby
client.create_commands_channel("commands.new-service")
client.create_queries_channel("queries.new-service")

client.list_commands_channels.each { |ch| puts "CMD: #{ch.name}" }
client.list_queries_channels.each { |ch| puts "QRY: #{ch.name}" }

client.delete_commands_channel("commands.old-service")
client.delete_queries_channel("queries.old-service")
```

## Error Handling

```ruby
begin
  response = client.send_command(cmd)
rescue KubeMQ::TimeoutError => e
  warn "Command timed out (#{e.code}) — #{e.suggestion}"
  retry if e.retryable?
rescue KubeMQ::ConnectionError => e
  warn "Broker unreachable: #{e.message}"
rescue KubeMQ::Error => e
  warn "#{e.class}: #{e.message}"
end
```

See [Error Handling](error-handling.md) for the full error hierarchy.
