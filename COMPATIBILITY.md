# Compatibility

This document describes supported language runtimes, platforms, dependency versions, and broker requirements for the `kubemq` gem.

## Ruby

| Version | Status |
| ------- | ------ |
| 3.1     | Supported |
| 3.2     | Supported |
| 3.3     | Supported |
| 4.0     | **Not supported** — the `grpc` gem does not yet ship precompiled native gems for Ruby 4.0; install may fail or require a from-source build. |

**JRuby** and **TruffleRuby** are **not supported**. The gRPC Ruby implementation relies on a C extension that is not compatible with those runtimes.

## Operating systems

The `grpc` gem provides prebuilt binaries for common platforms:

| OS | Architectures |
| -- | ------------- |
| Linux | x86_64, aarch64 |
| macOS | x86_64 (Intel), arm64 (Apple Silicon) |
| Windows | x64 (`x64-mingw-ucrt`) |

Other platforms may work only if `grpc` can compile from source with a suitable toolchain.

## Gem dependencies

| Gem | Requirement | Notes |
| --- | ----------- | ----- |
| `grpc` | `~> 1.65` | gRPC client; native extension |
| `google-protobuf` | `~> 4.0` | Protobuf runtime |

## KubeMQ server and protocol

| Component | Requirement |
| --------- | ----------- |
| KubeMQ server | **>= 2.0** |
| Protobuf / API definition | **v1.4.0** (see repository `kubemq.proto`) |

## CI verification

GitHub Actions runs the test suite on Ruby **3.1**, **3.2**, and **3.3** on Ubuntu against a KubeMQ broker service container. That matrix is the authoritative statement of what we routinely verify in automation; other combinations may still work but are best-effort.
