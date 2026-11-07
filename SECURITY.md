# Security Policy

Orc Harness runs coding agents on your machine and holds their secrets, so security
reports are welcome and taken seriously.

## Reporting

Please **do not** open a public issue. Use
[GitHub private vulnerability reporting](https://github.com/Lukitaduarte/orc-harness/security/advisories/new).
You should get a reply within a week.

## Supported versions

Only the latest release gets fixes.

## Model

- The daemon (`orcd`) accepts only devices paired with a ticket from its local socket
  or from an already-paired device. Traffic is end-to-end encrypted (iroh / QUIC).
- Env values and the daemon key live in the macOS Keychain, never in files or the app.
- Deploys, store releases, pushes to `main`, merges and package publishing wait for
  approval in the app; the hook fails closed. The local socket cannot approve.
