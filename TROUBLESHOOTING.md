# Troubleshooting

Common issues and solutions for the KubeMQ Ruby SDK.

## Connection Issues

### "Failed to connect to localhost:50000"

**Cause:** The KubeMQ broker is not running or is on a different address.

**Solutions:**

1. Verify the broker is running:
   ```bash
   docker ps | grep kubemq
   ```
2. Check the address:
   ```ruby
   client = KubeMQ::PubSubClient.new(
     address: ENV.fetch("KUBEMQ_ADDRESS", "localhost:50000")
   )
   ```
3. Test connectivity:
   ```bash
   grpcurl -plaintext localhost:50000 list
   ```
4. Check firewall rules — ensure port 50000 is open.

### "Connection is not ready"

**Cause:** The client tried an operation before the gRPC connection was fully established. Connections are established lazily on first use.

**Solutions:**

- Use `ping` to force and verify the connection:
  ```ruby
  client = KubeMQ::PubSubClient.new(address: "localhost:50000")
  info = client.ping
  puts "Connected to #{info.host}"
  ```
- If the error persists, check the reconnect policy:
  ```ruby
  KubeMQ.configure do |c|
    c.reconnect_policy.max_delay = 10.0
    c.reconnect_policy.max_attempts = 5
  end
  ```

## Authentication Errors

### "AUTH_FAILED — Verify auth token is valid and not expired"

**Cause:** The auth token is missing, invalid, or expired.

**Solutions:**

1. Set the token via environment variable:
   ```bash
   export KUBEMQ_AUTH_TOKEN="your-token-here"
   ```
2. Or pass it directly:
   ```ruby
   client = KubeMQ::PubSubClient.new(
     address: "localhost:50000",
     auth_token: ENV.fetch("KUBEMQ_AUTH_TOKEN")
   )
   ```
3. Check token expiration — tokens are JWTs; decode to verify the `exp` claim.
4. Verify the broker requires authentication — some dev instances run without auth.

### "PERMISSION_DENIED"

**Cause:** The token is valid but lacks required permissions for the operation.

**Solution:** Check the broker's access control configuration. The token may need additional claims for the channel or operation.

## TLS Errors

### "SSL_ERROR_SSL: certificate verify failed"

**Cause:** The server certificate doesn't match the CA or hostname.

**Solutions:**

1. Verify the CA file matches the broker's certificate chain:
   ```ruby
   c.tls = KubeMQ::TLSConfig.new(
     enabled: true,
     ca_file: "/certs/ca.pem"
   )
   ```
2. For development only, skip verification:
   ```ruby
   c.tls = KubeMQ::TLSConfig.new(
     enabled: true,
     insecure_skip_verify: true
   )
   ```

### "TLS cert_file is required when key_file is set"

**Cause:** `cert_file` and `key_file` must be provided together for mTLS.

**Solution:** Provide both files:
```ruby
c.tls = KubeMQ::TLSConfig.new(
  enabled: true,
  cert_file: "/certs/client.pem",
  key_file: "/certs/client-key.pem",
  ca_file: "/certs/ca.pem"
)
```

## Subscription Stops Receiving

**Symptoms:** The subscription block stops being called with no error.

**Possible causes and solutions:**

1. **CancellationToken was cancelled** — Check the token:
   ```ruby
   puts token.cancelled?
   ```
2. **Unhandled exception in the block** — Wrap your callback logic:
   ```ruby
   client.subscribe_to_events(sub, cancellation_token: token) do |event|
     begin
       process(event)
     rescue => e
       warn "Callback error: #{e.message}"
     end
   end
   ```
3. **No on_error callback** — Always provide one to catch stream-level errors:
   ```ruby
   client.subscribe_to_events(
     sub,
     cancellation_token: token,
     on_error: ->(err) { warn "Stream error: #{err.message}" }
   ) { |event| process(event) }
   ```
4. **Client was closed** — Check `client.closed?`
5. **Broker restarted** — The subscription should auto-reconnect. Check logs with `log_level: :debug`.

## Queue Visibility Timeout

### Messages Keep Reappearing

**Cause:** Messages are not being acknowledged before the broker's visibility timeout expires.

**Solutions:**

1. Acknowledge messages promptly:
   ```ruby
   response.messages.each do |msg|
     process(msg.body)
     msg.ack
   end
   ```
2. Use `auto_ack: true` for fire-and-forget processing:
   ```ruby
   request = KubeMQ::Queues::QueuePollRequest.new(
     channel: "queues.tasks",
     max_items: 1,
     wait_timeout: 5,
     auto_ack: true
   )
   ```
3. Configure a dead-letter policy for poison messages:
   ```ruby
   policy = KubeMQ::Queues::QueueMessagePolicy.new(
     max_receive_count: 3,
     max_receive_queue: "queues.tasks.dlq"
   )
   ```

## StreamBrokenError

### "Stream broke — N unacked messages"

**Cause:** The bidirectional gRPC stream was interrupted (network issue, broker restart, idle timeout).

**Solutions:**

1. Recreate the sender or receiver:
   ```ruby
   begin
     sender.publish(msg)
   rescue KubeMQ::StreamBrokenError => e
     warn "Unacked: #{e.unacked_message_ids}"
     sender = client.create_upstream_sender
     retry
   end
   ```
2. Subscription streams auto-reconnect — no action needed for `subscribe_to_*` methods.
3. Check network stability and keepalive settings:
   ```ruby
   KubeMQ.configure do |c|
     c.keepalive = KubeMQ::KeepAliveConfig.new(
       ping_interval_seconds: 5,
       ping_timeout_seconds: 3
     )
   end
   ```

## BufferFullError

### "Buffer full — messages dropped"

**Cause:** The reconnect buffer (capacity 1000) is full. During disconnection, outbound messages are buffered. When full, the oldest message is dropped.

**Solutions:**

1. Reduce send rate during outages:
   ```ruby
   begin
     client.send_event(msg)
   rescue KubeMQ::BufferFullError => e
     warn "Buffer full (#{e.buffer_size}) — waiting"
     sleep 5
     retry
   end
   ```
2. Check broker connectivity — the buffer fills because the connection is down.
3. Consider whether dropped messages are acceptable for your use case. For guaranteed delivery, use queues instead of events.

## Performance

### Slow Message Throughput

1. **Use the stream API** instead of simple API for queues:
   ```ruby
   sender = client.create_upstream_sender
   messages.each { |msg| sender.publish(msg) }
   sender.close
   ```
2. **Use streaming senders** for events:
   ```ruby
   sender = client.create_events_sender
   events.each { |e| sender.publish(e) }
   sender.close
   ```
3. **Poll in batches** instead of one-at-a-time:
   ```ruby
   request = KubeMQ::Queues::QueuePollRequest.new(
     channel: "queues.tasks",
     max_items: 100,
     wait_timeout: 5
   )
   ```
4. **Tune keepalive** — reduce unnecessary pings on stable networks.

## Debug Logging

Enable verbose SDK logging to diagnose issues:

```ruby
KubeMQ.configure do |c|
  c.log_level = :debug
end
```

For gRPC-level tracing, set environment variables before starting your application:

```bash
GRPC_VERBOSITY=debug GRPC_TRACE=all ruby my_app.rb
```

This produces detailed output for every gRPC call, connection state change, and keepalive ping. Disable in production.

### Reading Error Context

Every `KubeMQ::Error` includes structured context:

```ruby
rescue KubeMQ::Error => e
  puts "Operation: #{e.operation}"
  puts "Channel:   #{e.channel}"
  puts "Code:      #{e.code}"
  puts "Retryable: #{e.retryable?}"
  puts "Suggestion: #{e.suggestion}"
  puts "Cause:     #{e.cause&.class}"
end
```

See also: [Error Handling](docs/error-handling.md) for the full error hierarchy and rescue patterns.
