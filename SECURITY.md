# Security Policy

## Supported Versions

Security updates are applied to the latest minor release line of the current major version published on [RubyGems.org](https://rubygems.org/gems/kubemq).

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| Pre-1.0 | :x:                |

When in doubt, upgrade to the latest `1.x` release.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report them privately:

1. Email **support@kubemq.io** with a clear subject line (e.g. `[SECURITY] kubemq-ruby`).
2. Include:
   - A description of the issue and its impact
   - Steps to reproduce (or a proof of concept), if possible
   - Affected gem version(s) and Ruby version / OS, if relevant

We aim to acknowledge reports within a few business days and to coordinate disclosure after a fix is available.

## Scope

This policy covers the `kubemq` Ruby gem and its first-party code. Issues in upstream dependencies (for example the `grpc` or `google-protobuf` gems) should be reported to their respective maintainers; we will bump dependencies when patched versions are available.
