# Error Handling

All KubeMQ SDK errors inherit from `KubeMQ::Error`. Each error carries structured context: an error code, retryable flag, originating operation, channel name, and an actionable suggestion.

## Error Hierarchy

```
KubeMQ::Error                  # Base — #retryable?, #code, #suggestion
├── KubeMQ::ConnectionError    # Connectivity / transport failures (retryable)
│   └── KubeMQ::AuthenticationError  # Invalid/expired credentials (not retryable)
├── KubeMQ::TimeoutError       # Deadline exceeded (retryable)
├── KubeMQ::ValidationError    # Invalid request parameters (not retryable)
├── KubeMQ::ConfigurationError # Invalid client config (not retryable)
├── KubeMQ::ChannelError       # Channel-level broker errors
├── KubeMQ::MessageError       # Send failures, rate limiting
├── KubeMQ::TransactionError   # Queue ack/reject/requeue failures
├── KubeMQ::ClientClosedError  # Use-after-close (not retryable)
├── KubeMQ::ConnectionNotReadyError  # Op before connection ready (retryable)
├── KubeMQ::StreamBrokenError  # Broken gRPC stream (#unacked_message_ids)
├── KubeMQ::BufferFullError    # Reconnect buffer saturated (#buffer_size)
└── KubeMQ::CancellationError  # Cooperative cancel via CancellationToken
```

## Error Codes

Every error has a `code` attribute from `KubeMQ::ErrorCode`:

| Code | Category | Retryable? | Suggestion |
|------|----------|:----------:|------------|
| `CONNECTION_TIMEOUT` | Timeout | Yes | Increase timeout or check server load |
| `UNAVAILABLE` | Transient | Yes | Check server connectivity and firewall rules |
| `CONNECTION_NOT_READY` | Transient | Yes | Wait for client to connect or check server |
| `AUTH_FAILED` | Authentication | No | Verify auth token is valid and not expired |
| `PERMISSION_DENIED` | Authorization | No | Verify credentials have required permissions |
| `VALIDATION_ERROR` | Validation | No | Check request parameters |
| `ALREADY_EXISTS` | Validation | No | Resource already exists |
| `OUT_OF_RANGE` | Validation | No | Check pagination or sequence numbers |
| `NOT_FOUND` | Not Found | No | Verify channel/queue exists or create it |
| `RESOURCE_EXHAUSTED` | Throttling | Yes | Reduce send rate or increase capacity |
| `ABORTED` | Transient | Yes | Retry may succeed |
| `INTERNAL` | Fatal | No | Check server logs |
| `UNKNOWN` | Transient | Yes | Check server logs |
| `UNIMPLEMENTED` | Fatal | No | Check server version |
| `DATA_LOSS` | Fatal | No | Check server storage |
| `CANCELLED` | Cancellation | No | Intentional cancellation |
| `BUFFER_FULL` | Backpressure | No | Wait for recovery or increase buffer |
| `STREAM_BROKEN` | Transient | Yes | Recreate sender/receiver |
| `CLIENT_CLOSED` | Fatal | No | Create a new client instance |
| `CONFIGURATION_ERROR` | Validation | No | Check address, TLS, credentials |
| `CALLBACK_ERROR` | Runtime | No | Fix the callback code |

## gRPC Status Code Mapping

The SDK automatically maps gRPC errors to typed exceptions. Application code should rescue `KubeMQ::Error` subclasses, not raw `GRPC::BadStatus`:

| gRPC Code | SDK Exception | Error Code | Retryable? |
|-----------|--------------|------------|:----------:|
| `CANCELLED` | `CancellationError` | `CANCELLED` | No |
| `UNKNOWN` | `Error` | `UNKNOWN` | Yes |
| `INVALID_ARGUMENT` | `ValidationError` | `VALIDATION_ERROR` | No |
| `DEADLINE_EXCEEDED` | `TimeoutError` | `CONNECTION_TIMEOUT` | Yes |
| `NOT_FOUND` | `ChannelError` | `NOT_FOUND` | No |
| `ALREADY_EXISTS` | `ValidationError` | `ALREADY_EXISTS` | No |
| `PERMISSION_DENIED` | `AuthenticationError` | `PERMISSION_DENIED` | No |
| `RESOURCE_EXHAUSTED` | `MessageError` | `RESOURCE_EXHAUSTED` | Yes |
| `FAILED_PRECONDITION` | `ValidationError` | `VALIDATION_ERROR` | No |
| `ABORTED` | `TransactionError` | `ABORTED` | Yes |
| `OUT_OF_RANGE` | `ValidationError` | `OUT_OF_RANGE` | No |
| `UNIMPLEMENTED` | `Error` | `UNIMPLEMENTED` | No |
| `INTERNAL` | `Error` | `INTERNAL` | No |
| `UNAVAILABLE` | `ConnectionError` | `UNAVAILABLE` | Yes |
| `DATA_LOSS` | `Error` | `DATA_LOSS` | No |
| `UNAUTHENTICATED` | `AuthenticationError` | `AUTH_FAILED` | No |

## Rescue Patterns

### Generic Error Handling

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::Error => e
  warn "#{e.class}: #{e.message} (code=#{e.code})"
  warn "Suggestion: #{e.suggestion}" if e.suggestion
end
```

### Targeted Recovery by Subclass

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::TimeoutError => e
  retry if e.retryable?
rescue KubeMQ::ValidationError => e
  warn "Fix input: #{e.suggestion}"
rescue KubeMQ::AuthenticationError => e
  warn "Auth failed — check credentials"
rescue KubeMQ::ClientClosedError
  client = KubeMQ::PubSubClient.new
  retry
rescue KubeMQ::Error => e
  warn "Unhandled: #{e.message}"
end
```

### Retryable Error Loop

```ruby
max_retries = 3
attempt = 0

begin
  client.send_event(msg)
rescue KubeMQ::Error => e
  if e.retryable? && (attempt += 1) <= max_retries
    sleep(2**attempt)
    retry
  end
  raise
end
```

### StreamBrokenError Recovery

Queue stream senders and receivers must be recreated after a broken stream:

```ruby
sender = client.create_upstream_sender

begin
  sender.publish(msg)
rescue KubeMQ::StreamBrokenError => e
  warn "Stream broke — #{e.unacked_message_ids.size} unacked"
  sender = client.create_upstream_sender
  retry
end
```

### BufferFullError

During disconnection, outbound messages are buffered. When the buffer is full, the oldest message is dropped:

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::BufferFullError => e
  warn "Buffer full (#{e.buffer_size} messages) — slowing down"
  sleep 5
  retry
end
```

## Error Classification

Classify errors programmatically for routing or metrics:

```ruby
begin
  client.send_event(msg)
rescue KubeMQ::Error => e
  category, retryable = KubeMQ.classify_error(e)

  case category
  when KubeMQ::ErrorCategory::TRANSIENT
    retry if retryable
  when KubeMQ::ErrorCategory::AUTHENTICATION
    refresh_token!
  when KubeMQ::ErrorCategory::VALIDATION
    log_invalid_request(e)
  when KubeMQ::ErrorCategory::FATAL
    alert_operations_team(e)
  end
end
```

### Lookup Suggestions

```ruby
suggestion = KubeMQ.suggestion_for(KubeMQ::ErrorCode::UNAVAILABLE)
# => "Check server connectivity and firewall rules."
```

## Error Context Fields

Every `KubeMQ::Error` exposes structured context:

| Field | Type | Description |
|-------|------|-------------|
| `code` | `String, nil` | Error code from `ErrorCode` |
| `message` | `String` | Human-readable description |
| `operation` | `String` | SDK operation that failed (e.g., `"send_event"`) |
| `channel` | `String, nil` | Channel name involved |
| `request_id` | `String` | Correlation ID |
| `suggestion` | `String, nil` | Actionable recovery suggestion |
| `details` | `Hash` | Additional context |
| `cause` | `Exception, nil` | Original underlying exception |
| `retryable?` | `Boolean` | Whether the operation may succeed on retry |

See also: [Troubleshooting](../TROUBLESHOOTING.md) for common problems and solutions.
