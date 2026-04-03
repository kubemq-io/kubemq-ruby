# KubeMQ Ruby SDK

Official Ruby client for [KubeMQ](https://kubemq.io) — Events, Events Store, Queues (stream and simple APIs), Commands, and Queries over gRPC.

[![Gem Version](https://img.shields.io/gem/v/kubemq.svg)](https://rubygems.org/gems/kubemq)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/kubemq-io/kubemq-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/kubemq-io/kubemq-ruby/actions/workflows/ci.yml)

## Table of Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Features](#features)
- [Configuration](#configuration)
- [Error handling](#error-handling)
- [Reconnection](#reconnection)
- [Examples](#examples)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add to your `Gemfile`:

```ruby
gem "kubemq", "~> 1.0"
```

Then:

```bash
bundle install
```

Or install directly:

```bash
gem install kubemq
```

**Requirements:** Ruby **>= 3.1**, `grpc` **~> 1.65**, `google-protobuf` **~> 4.0**. See [COMPATIBILITY.md](COMPATIBILITY.md) for platforms and Ruby 4.0 limitations.

## Quick start

All clients connect lazily on first use. Default address is `localhost:50000` unless you override configuration (see below).

### Pub/Sub (Events)

```ruby
require "kubemq"

client = KubeMQ::PubSubClient.new(address: "localhost:50000", client_id: "my-app")
client.send_event(
  KubeMQ::PubSub::EventMessage.new(channel: "events.hello", body: "Hello, KubeMQ!")
)
client.close
```

### Queues (simple send / receive)

```ruby
require "kubemq"

qc = KubeMQ::QueuesClient.new(address: "localhost:50000", client_id: "queue-worker")
msg = KubeMQ::Queues::QueueMessage.new(channel: "jobs", metadata: "type", body: "process-me")
qc.send_queue_message(msg)
received = qc.receive_queue_messages(channel: "jobs", max_messages: 1, wait_timeout_seconds: 5)
received.each { |m| puts m.body }
qc.close
```

### Commands (RPC)

Command and query **`timeout` values are in milliseconds** (proto-aligned).

```ruby
require "kubemq"

cq = KubeMQ::CQClient.new(address: "localhost:50000", client_id: "cmd-client")
response = cq.send_command(
  KubeMQ::CQ::CommandMessage.new(
    channel: "commands",
    metadata: "ping",
    body: "hello",
    timeout: 10_000
  )
)
puts "executed=#{response.executed}, error=#{response.error}"
cq.close
```

### Queries (RPC, optional cache)

```ruby
require "kubemq"

cq = KubeMQ::CQClient.new(address: "localhost:50000", client_id: "query-client")
response = cq.send_query(
  KubeMQ::CQ::QueryMessage.new(
    channel: "queries",
    metadata: "lookup",
    body: "key-1",
    timeout: 10_000
  )
)
puts "body=#{response.body}, cache_hit=#{response.cache_hit}"
cq.close
```

Subscriptions (events, events store, commands, queries) run on a background thread and take a Ruby block; use `KubeMQ::CancellationToken` to stop them. See the `examples/` directory for full flows.

## Features

- **Events** — Fire-and-forget pub/sub, wildcards, consumer groups, streaming batch senders
- **Events Store** — Durable events with replay from sequence, time, or position policies
- **Queues — stream** — Upstream/downstream streaming, poll, transactions, ack/nack, policies
- **Queues — simple** — Unary send/receive/batch helpers
- **Commands** — Request/response RPC with timeouts
- **Queries** — RPC with optional cache key / TTL
- **Channel management** — Create, delete, list, and purge queue channels
- **Auto-reconnect** — Exponential backoff with jitter; bounded buffer during outages (oldest dropped when full)
- **TLS / mTLS** — Via `Configuration#tls`
- **OpenTelemetry** — Optional instrumentation (soft dependency)

## Configuration

Settings are resolved in this order (**highest precedence first**):

1. Arguments passed to the client constructor (`address:`, `client_id:`, `auth_token:`, or a full `Configuration` object)
2. Values set in `KubeMQ.configure { ... }`
3. Environment variables, then built-in defaults

### `KubeMQ.configure`

```ruby
KubeMQ.configure do |c|
  c.address = "kubemq.example.com:50000"
  c.auth_token = ENV.fetch("KUBEMQ_AUTH_TOKEN", nil)
  c.reconnect_policy.max_delay = 60.0
end

client = KubeMQ::PubSubClient.new # uses global configuration
```

### Environment variables

| Variable | Purpose |
| -------- | ------- |
| `KUBEMQ_ADDRESS` | Broker host:port (default `localhost:50000`) |
| `KUBEMQ_AUTH_TOKEN` | Optional bearer token sent as gRPC metadata |

### Common defaults (`KubeMQ::Configuration`)

| Field | Default | Notes |
| ----- | ------- | ----- |
| `address` | `ENV["KUBEMQ_ADDRESS"]` or `localhost:50000` | |
| `client_id` | Auto-generated id | Prefix `kubemq-ruby-` + random hex |
| `auth_token` | `ENV["KUBEMQ_AUTH_TOKEN"]` | |
| `tls` | `TLSConfig` (disabled by default) | Client cert, key, CA, `insecure_skip_verify` |
| `keepalive` | 10s ping, 5s timeout, `permit_without_calls: true` | |
| `reconnect_policy` | Enabled, 1s base, 2x multiplier, 30s max, 25% jitter, unlimited attempts (`max_attempts: 0`) | |
| `max_send_size` / `max_receive_size` | 100 MB each | Client-side gRPC limits |
| `log_level` | `:warn` | |

Queue **`wait_timeout_seconds`** and related simple-API timeouts use **seconds**. Command/query **`timeout`** uses **milliseconds**.

## Error handling

All SDK errors inherit `KubeMQ::Error`. Rescue the base type for generic handling, or specific subclasses for targeted logic.

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::ValidationError => e
  warn e.suggestion
rescue KubeMQ::TimeoutError => e
  retry if e.retryable?
rescue KubeMQ::Error => e
  warn "#{e.class}: #{e.message}"
end
```

**Hierarchy (overview):**

- `KubeMQ::Error` — base; `#retryable?`, `#code`, `#suggestion`, context fields
- `KubeMQ::ConnectionError` — connectivity / transport
- `KubeMQ::AuthenticationError` — auth failures
- `KubeMQ::TimeoutError` — deadlines exceeded
- `KubeMQ::ValidationError` — invalid arguments
- `KubeMQ::ConfigurationError` — invalid config
- `KubeMQ::ChannelError` — channel-level broker errors
- `KubeMQ::MessageError` — malformed or rejected messages
- `KubeMQ::TransactionError` — queue transaction failures
- `KubeMQ::ClientClosedError` — use after `close`
- `KubeMQ::ConnectionNotReadyError` — operation before ready
- `KubeMQ::StreamBrokenError` — broken streaming call (`#unacked_message_ids` where applicable)
- `KubeMQ::BufferFullError` — reconnect buffer saturated (`#buffer_size`)
- `KubeMQ::CancellationError` — cooperative cancel

gRPC `GRPC::BadStatus` is mapped where appropriate; prefer rescuing `KubeMQ::Error` in application code.

## Reconnection

When `reconnect_policy.enabled` is true (default), the transport automatically reconnects after transient failures using exponential backoff (capped by `max_delay`) and jitter. While disconnected, outbound traffic uses a bounded buffer (capacity 1000); when full, **oldest** messages are dropped — same behavior as other official KubeMQ SDKs.

Streaming consumers are restarted after reconnect; **queue downstream transactions** are not replayed automatically — a new poll stream is established and server visibility timeouts apply.

Call `close` on clients for a clean shutdown; `close` is idempotent.

## Examples

Runnable scripts live under the `examples/` directory:

- `examples/connection/` — TLS, mTLS, auth, ping, close
- `examples/pubsub/`, `examples/events_store/`
- `examples/queues_simple/`, `examples/queues_stream/`
- `examples/commands/`, `examples/queries/`
- `examples/management/` — channels and purge

Set `KUBEMQ_ADDRESS` if your broker is not on `localhost:50000`.

## Documentation

- **Guides:** See the [docs/](docs/) directory for comprehensive guides.
- **YARD API Reference:** `bundle exec yard doc && open doc/index.html`
- **KubeMQ Documentation:** [https://docs.kubemq.io](https://docs.kubemq.io)
- **KubeMQ Website:** [https://kubemq.io](https://kubemq.io)
- **Community & Support:** [GitHub Issues](https://github.com/kubemq-io/kubemq-ruby/issues)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, `rake proto:generate`, tests, and the release process.

## License

Licensed under the **Apache License 2.0**. See [LICENSE](LICENSE).
