# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-02

### Added

- Initial release of the official KubeMQ Ruby SDK (`kubemq` gem).
- **Events (Pub/Sub):** `PubSubClient`, `send_event`, `subscribe_to_events`, wildcard channels, consumer groups, streaming senders.
- **Events Store:** `send_event_store`, `subscribe_to_events_store` with replay start positions (first, last, new, sequence, time, time delta).
- **Queues — stream API:** `send_queue_message_stream`, `poll` with upstream/downstream streaming, ack/nack, transactions, policies (delay, expiration, dead letter).
- **Queues — simple API:** `send_queue_message`, `send_queue_messages_batch`, `receive_queue_messages`, peek, ack helpers.
- **Commands:** `CQClient#send_command`, `subscribe_to_commands`, `send_response`.
- **Queries:** `send_query`, `subscribe_to_queries`, optional cache key/TTL on queries.
- **Channel management:** `create_channel`, `delete_channel`, `list_channels`, `purge_queue_channel` via internal query pattern.
- **Core:** `Configuration` with TLS, keepalive, reconnect policy; `KubeMQ.configure`; ENV `KUBEMQ_ADDRESS`, `KUBEMQ_AUTH_TOKEN`.
- **Transport:** gRPC client with interceptors (auth, metrics, retry, error mapping), reconnect with exponential backoff and jitter, bounded buffer during disconnect.
- **Errors:** `KubeMQ::Error` hierarchy with gRPC status mapping, suggestions, and `retryable?`.
- **Cancellation:** `CancellationToken` for cooperative shutdown of subscriptions.
- **OpenTelemetry:** optional soft dependency for custom messaging spans.
- **Proto:** Ruby stubs for KubeMQ API **v1.4.0**, checked into `lib/kubemq/proto/`.
- **Testing:** RSpec unit and integration suites; SimpleCov minimum 95% line coverage (excluding generated proto).
- **Examples:** runnable samples under `examples/` (connection, pub/sub, events store, queues, commands, queries, management).
- **Burn-in:** standalone app under `burnin/` for soak testing and dashboard integration.

[1.0.0]: https://github.com/kubemq-io/kubemq-ruby/releases/tag/v1.0.0
