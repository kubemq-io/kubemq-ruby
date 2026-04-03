# Getting Started with KubeMQ Ruby SDK

This guide walks you from zero to a working KubeMQ application in under five minutes.

## Prerequisites

- **Ruby** >= 3.1
- **Bundler** >= 2.0
- A running **KubeMQ broker** — the quickest option is Docker:

```bash
docker run -d -p 50000:50000 -p 9090:9090 kubemq/kubemq:latest
```

Port 50000 is the gRPC endpoint; port 9090 is the optional web dashboard.

## Install

Add the gem to your `Gemfile`:

```ruby
gem "kubemq", "~> 1.0"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install kubemq
```

## Connect and Ping

Verify connectivity with a three-line health check:

```ruby
require "kubemq"

client = KubeMQ::PubSubClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "getting-started"
)

info = client.ping
puts "Connected to #{info.host} running KubeMQ v#{info.version}"
client.close
```

## Send Your First Event

Events use fire-and-forget semantics — fast, with no persistence guarantee:

```ruby
require "kubemq"

client = KubeMQ::PubSubClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "event-sender"
)

result = client.send_event(
  KubeMQ::PubSub::EventMessage.new(
    channel: "events.hello",
    body: "Hello from Ruby!"
  )
)
puts "Event sent: #{result.id}" if result.sent
client.close
```

## Subscribe to Events

Subscriptions run on a background thread. Use a `CancellationToken` to stop:

```ruby
require "kubemq"

client = KubeMQ::PubSubClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "event-receiver"
)

token = KubeMQ::CancellationToken.new
sub = KubeMQ::PubSub::EventsSubscription.new(channel: "events.hello")

client.subscribe_to_events(sub, cancellation_token: token) do |event|
  puts "Received on '#{event.channel}': #{event.body}"
end

sleep 1
client.send_event(
  KubeMQ::PubSub::EventMessage.new(channel: "events.hello", body: "Hello from Ruby!")
)
sleep 2
token.cancel
client.close
```

## Send and Receive a Queue Message

Queues provide guaranteed, exactly-once delivery:

```ruby
require "kubemq"

client = KubeMQ::QueuesClient.new(
  address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000"),
  client_id: "queue-worker"
)

client.send_queue_message(
  KubeMQ::Queues::QueueMessage.new(
    channel: "queues.tasks",
    body: '{"task": "process-order", "id": 42}'
  )
)

request = KubeMQ::Queues::QueuePollRequest.new(
  channel: "queues.tasks",
  max_items: 1,
  wait_timeout: 5
)
response = client.poll(request)

unless response.error?
  response.messages.each do |msg|
    puts "Got task: #{msg.body}"
    msg.ack
  end
end

client.close
```

## Next Steps

| Topic | Guide |
|-------|-------|
| Events & durable events store | [Events & Pub/Sub](events-pubsub.md) |
| Queue messaging | [Queues](queues.md) |
| RPC commands & queries | [Commands & Queries](commands-queries.md) |
| All configuration options | [Configuration Reference](configuration.md) |
| Error handling patterns | [Error Handling](error-handling.md) |
| Common problems | [Troubleshooting](../TROUBLESHOOTING.md) |
| Runnable scripts | `examples/` directory |
| API reference | Run `bundle exec yard doc && open doc/index.html` |
