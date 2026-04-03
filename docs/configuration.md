# Configuration Reference

All KubeMQ clients share a unified `KubeMQ::Configuration` object. Settings are resolved in precedence order (highest first):

1. **Constructor arguments** — `KubeMQ::PubSubClient.new(address: "...")` 
2. **`KubeMQ.configure` block** — global defaults
3. **Environment variables** — `KUBEMQ_ADDRESS`, `KUBEMQ_AUTH_TOKEN`
4. **Built-in defaults**

## Global Configuration

```ruby
require "kubemq"

KubeMQ.configure do |c|
  c.address = "kubemq.example.com:50000"
  c.auth_token = ENV.fetch("KUBEMQ_AUTH_TOKEN", nil)
  c.log_level = :info
  c.reconnect_policy.max_delay = 60.0
end

client = KubeMQ::PubSubClient.new
```

## Per-Client Configuration

```ruby
config = KubeMQ::Configuration.new(
  address: "broker-2.example.com:50000",
  client_id: "worker-1",
  log_level: :debug
)
client = KubeMQ::QueuesClient.new(config: config)
```

## Complete Configuration Table

| Field | Type | Default | Env Var | Description |
|-------|------|---------|---------|-------------|
| `address` | `String` | `"localhost:50000"` | `KUBEMQ_ADDRESS` | Broker host:port |
| `client_id` | `String` | Auto-generated | — | Unique client identifier (`kubemq-ruby-` + random hex) |
| `auth_token` | `String, nil` | `nil` | `KUBEMQ_AUTH_TOKEN` | Bearer token for authentication |
| `tls` | `TLSConfig` | Disabled | — | TLS/mTLS configuration (see below) |
| `keepalive` | `KeepAliveConfig` | Enabled | — | gRPC keepalive settings (see below) |
| `reconnect_policy` | `ReconnectPolicy` | Enabled | — | Auto-reconnect policy (see below) |
| `max_send_size` | `Integer` | `104_857_600` (100 MB) | — | Maximum outbound message size in bytes |
| `max_receive_size` | `Integer` | `104_857_600` (100 MB) | — | Maximum inbound message size in bytes |
| `log_level` | `Symbol` | `:warn` | — | Log verbosity: `:debug`, `:info`, `:warn`, `:error` |
| `default_timeout` | `Integer` | `30` | — | Default gRPC deadline in seconds |

## TLS / mTLS Setup

Configure secure connections via `KubeMQ::TLSConfig`.

### Server TLS (Verify Broker Certificate)

```ruby
KubeMQ.configure do |c|
  c.address = "kubemq.example.com:50000"
  c.tls = KubeMQ::TLSConfig.new(
    enabled: true,
    ca_file: "/certs/ca.pem"
  )
end
```

### Mutual TLS (mTLS)

```ruby
KubeMQ.configure do |c|
  c.address = "kubemq.example.com:50000"
  c.tls = KubeMQ::TLSConfig.new(
    enabled: true,
    cert_file: "/certs/client.pem",
    key_file: "/certs/client-key.pem",
    ca_file: "/certs/ca.pem"
  )
end
```

### Skip Verification (Development Only)

```ruby
c.tls = KubeMQ::TLSConfig.new(
  enabled: true,
  insecure_skip_verify: true
)
```

### TLS Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `Boolean` | `false` | Enable TLS |
| `cert_file` | `String, nil` | `nil` | Client certificate PEM path |
| `key_file` | `String, nil` | `nil` | Client private key PEM path |
| `ca_file` | `String, nil` | `nil` | CA certificate PEM path |
| `insecure_skip_verify` | `Boolean` | `false` | Skip server cert verification |

> **Note:** `cert_file` and `key_file` must be provided together. Setting one without the other raises `ConfigurationError`.

## Keepalive Settings

Configure gRPC keepalive via `KubeMQ::KeepAliveConfig`. Keepalive detects dead connections and prevents firewalls from closing idle connections.

```ruby
KubeMQ.configure do |c|
  c.keepalive = KubeMQ::KeepAliveConfig.new(
    enabled: true,
    ping_interval_seconds: 5,
    ping_timeout_seconds: 3,
    permit_without_calls: true
  )
end
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `Boolean` | `true` | Enable gRPC keepalive pings |
| `ping_interval_seconds` | `Integer` | `10` | Seconds between pings |
| `ping_timeout_seconds` | `Integer` | `5` | Seconds to wait for ping response |
| `permit_without_calls` | `Boolean` | `true` | Send pings even without active RPCs |

**Tuning guidance:** For flaky networks, reduce `ping_interval_seconds` to 5 and `ping_timeout_seconds` to 3. For stable networks with firewalls, the defaults are appropriate.

## Reconnect Policy

Configure auto-reconnect via `KubeMQ::ReconnectPolicy`. When enabled, the transport reconnects with exponential backoff after transient failures.

```ruby
KubeMQ.configure do |c|
  c.reconnect_policy = KubeMQ::ReconnectPolicy.new(
    enabled: true,
    base_interval: 2.0,
    multiplier: 2.0,
    max_delay: 60.0,
    jitter_percent: 0.25,
    max_attempts: 10
  )
end
```

The delay between attempts is computed as:

```
delay = min(base_interval * multiplier^(attempt-1), max_delay) ± jitter
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `Boolean` | `true` | Enable auto-reconnect |
| `base_interval` | `Float` | `1.0` | Initial delay in seconds |
| `multiplier` | `Float` | `2.0` | Backoff multiplier per attempt |
| `max_delay` | `Float` | `30.0` | Maximum delay cap in seconds |
| `jitter_percent` | `Float` | `0.25` | Jitter as a fraction of computed delay |
| `max_attempts` | `Integer` | `0` (unlimited) | Maximum reconnect attempts; `0` = unlimited |

**Tuning guidance:** For production, set `max_attempts: 0` (unlimited) and cap `max_delay` at 30–60 seconds. For tests, set `max_attempts: 3` to fail fast.

## Log Levels

Set `log_level` to control SDK log output:

| Level | Description |
|-------|-------------|
| `:debug` | Verbose — gRPC calls, reconnect attempts, stream lifecycle |
| `:info` | Connection events, subscription starts/stops |
| `:warn` | Recoverable issues — reconnect attempts, buffer warnings |
| `:error` | Unrecoverable failures only |

```ruby
KubeMQ.configure do |c|
  c.log_level = :debug
end
```

For gRPC-level debugging, also set the environment variable:

```bash
GRPC_VERBOSITY=debug GRPC_TRACE=all ruby my_app.rb
```

## gRPC Message Size Limits

The `max_send_size` and `max_receive_size` fields set client-side gRPC channel options. The defaults (100 MB each) match the broker's default limits. Increase only if the broker is also configured for larger messages:

```ruby
KubeMQ.configure do |c|
  c.max_send_size = 200 * 1024 * 1024
  c.max_receive_size = 200 * 1024 * 1024
end
```

## Resetting Configuration

Reset to defaults with:

```ruby
KubeMQ.reset_configuration!
```
