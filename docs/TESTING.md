# Testing

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`

Current tests: HTTP engine against local loopback servers (GET, POST, truncation, timeout, cancel, redirects incl. cross-origin header stripping, redirect loop, refused connection) and theme token presence.

Planned: Drift migration tests, editor unit/widget tests, Persian shaping and caret tests, golden/screenshot checks, import/export round-trips.

TLS failure, proxy and streaming of very large bodies are **not yet tested**.
