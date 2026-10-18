# Testing

## Run

```
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

`flutter test` needs the native SQLite library through `package:sqlite3` build hooks. The first run downloads/builds it, so an internet connection (or a populated pub cache) is needed once.

## What exists

| File | Covers |
|---|---|
| `test/features/http/io_http_engine_test.dart` | GET/POST, truncation, timeout, cancel, redirects (same origin, cross origin header stripping, never, loop), refused connection |
| `test/features/request_builder_test.dart` | scheme defaulting, query encoding, variables, auth types, masking, JSON/form/multipart/GraphQL bodies, size limits, settings applied |
| `test/features/variables_test.dart`, `testing_domain_test.dart`, `line_diff_test.dart` | precedence, secrets, JSONPath, assertions, extraction, diff |
| `test/features/settings_test.dart` | defaults, round trip, clamping, import errors, redaction |
| `test/features/curl_test.dart`, `import_export_test.dart` | cURL tokenizer/parser/exporter, Postman, PostBox, OpenAPI |
| `test/features/persistence_test.dart` | migrations, transactions, collections, history, environments (real SQLite) |
| `test/features/oauth_test.dart` | PKCE, full loopback flow against fake servers, state mismatch, errors |
| `test/features/streaming_test.dart` | SSE parser and session, WebSocket echo |
| `test/features/workspace_flow_test.dart` | cubits end to end: send, assertions, chaining, history privacy, save/secrets, runner |
| `test/ui/editor_logic_test.dart` | JSON tools, highlighter, bracket matching, auto-close/indent, find/replace |
| `test/ui/design_contrast_test.dart` | contrast of all themes |
| `test/l10n_test.dart` | EN/FA key and placeholder parity |
| `test/ui/widgets_test.dart` | editor widget, desktop/phone/Persian smoke tests, sending to a closed port |

## Not covered yet

- TLS failure against a self-signed server, proxy behaviour, very large streamed bodies
- Real keystore behaviour (`flutter_secure_storage`), Android OAuth redirect, `url_launcher`
- Typing, selection and caret behaviour with real IMEs and mixed RTL text (the editor is only widget-tested)
- Golden/screenshot tests, accessibility audits, performance benchmarks
- Release builds on any platform

## Policy

A failing test is never skipped silently; if one cannot be fixed it is documented in `PROJECT_STATUS.md` with the reason.
