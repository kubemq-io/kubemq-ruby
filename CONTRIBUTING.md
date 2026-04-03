# Contributing to KubeMQ Ruby

Thank you for your interest in improving the official KubeMQ Ruby SDK. This guide covers local development, testing, style, and releases.

## Development setup

- **Ruby:** Use **3.3** locally for day-to-day work. Continuous integration also runs **3.1** and **3.2** (see [COMPATIBILITY.md](COMPATIBILITY.md)).
- **Broker:** Integration tests expect a KubeMQ server at `KUBEMQ_ADDRESS` (default `localhost:50000`).

```bash
git clone https://github.com/kubemq-io/kubemq-ruby.git
cd kubemq-ruby
bundle install
```

## Build and test commands

| Task | Command |
| ---- | ------- |
| Default (lint + spec) | `bundle exec rake` |
| Lint | `bundle exec rubocop` |
| Auto-correct (where safe) | `bundle exec rubocop -A` |
| Tests | `bundle exec rspec` |
| Coverage | Loaded automatically from `spec/spec_helper.rb` via SimpleCov (**95%** minimum); there is no separate `simplecov` CLI step |
| API docs | `bundle exec yard doc` |

## Code style

- Follow [RuboCop](https://rubocop.org/) as configured in [`.rubocop.yml`](.rubocop.yml) (target Ruby **3.1**, generated proto excluded).
- Use `# frozen_string_literal: true` at the top of new Ruby files unless there is a strong reason not to.
- Prefer idiomatic Ruby: keyword arguments, `snake_case`, small focused methods.
- Do not run RuboCop on `lib/kubemq/proto/`; those files are generated.

## Proto regeneration

Stubs are checked into `lib/kubemq/proto/`. Regenerate after `kubemq.proto` changes:

1. From the **gem root** (`kubemq-ruby/`), ensure `grpc-tools` is available (`bundle install`).
2. Run:

```bash
bundle exec rake proto:generate
```

This invokes `grpc_tools_ruby_protoc` with **`-I ../`** and **`../kubemq.proto`**, assuming the canonical proto lives one directory above the gem (e.g. in the multi-SDK `clients` repo). If you vendor `kubemq.proto` inside the gem, adjust the Rake task to `-I .` and `kubemq.proto` and update this section.

## Pull requests

### Review process

1. Open a PR against `main` with a clear description and linked issue (if any).
2. Ensure `bundle exec rake` passes (RuboCop + RSpec with coverage).
3. Maintain or improve test coverage; avoid unrelated refactors in the same PR.

### PR template (copy into your PR description)

```markdown
## Summary
<!-- What does this change and why? -->

## Type of change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation only

## Testing
- [ ] `bundle exec rake`
- [ ] Integration tests run against local broker (if behavior changed)

## Checklist
- [ ] RuboCop clean
- [ ] Tests added/updated where appropriate
- [ ] CHANGELOG.md updated (user-visible changes)
```

## Release process (Trusted Publishing)

Releases are published to [RubyGems.org](https://rubygems.org/gems/kubemq) using **Trusted Publishing** (OpenID Connect from GitHub Actions).

1. Ensure [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) is configured for this repository and gem name.
2. Bump version in `lib/kubemq/version.rb` and update [CHANGELOG.md](CHANGELOG.md) on `main`.
3. Push an annotated tag matching `v*` (for example `v1.0.0`).
4. The [Release workflow](.github/workflows/release.yml) builds the gem with `gem build kubemq.gemspec` and runs `rubygems/release-gem@v1`.

If OIDC publishing fails (for example misconfiguration), you can fall back to a manual `gem push` using a RubyGems API key with MFA — only as a break-glass procedure.

## Burn-in app

The optional load harness lives under `burnin/` with its own `Gemfile`. See that directory and [README.md](README.md) for usage.
