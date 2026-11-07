# Contributing

Thanks for helping with Orc Harness. Work, work.

## Setup

You need stable Rust, Flutter 3.38+, and Claude Code (`claude`). `gh`, Chrome and
language servers (`dart`, `typescript-language-server`…) are optional; tests that
need them skip when they are missing.

```sh
cargo build --release --bins
cargo test --workspace
cd app && flutter pub get && flutter analyze && flutter test
```

During development, run the daemon apart from your real one:

```sh
ORC_HOME=~/.orc-dev ORC_SECRETS=file ./target/release/orcd serve
```

## Pull requests

- One change per PR, with tests for new behavior.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat(app): …`, `fix(daemon): …`).
- `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`,
  `flutter analyze` and `flutter test` must pass; CI runs them.
- UI text goes in `app/lib/l10n/app_en.arb` (and the other languages); see
  [Languages](README.md#languages).
- Secrets never go in files, logs, plans or the app: they live in the Keychain.

## Screenshots

`cd app && flutter test test_screenshots` regenerates `docs/screenshots/` from demo data.

## Reporting bugs and security issues

Bugs: open an issue with the template. Security: see [SECURITY.md](SECURITY.md).
