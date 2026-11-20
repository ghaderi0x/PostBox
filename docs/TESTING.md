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


## 0.4.0 tests

| File | Covers |
|---|---|
| `test/features/scripting_test.dart` | interpreter semantics, limits, pre/post scripts, secret invisibility |
| `test/features/cookie_jar_test.dart` | Set-Cookie parsing and rejection rules, matching, limits, persistence hooks |
| `test/features/inheritance_test.dart` | variable layers and sources, `NodeSettings`, inheritance, Postman and PostBox import/export of settings, scripts dropped on import, binary body export |
| `test/features/executor_features_test.dart` | executor against a local server: inherited auth and headers, variables, script order, cookies, binary body, build errors |
| `test/features/http/engine_features_test.dart` | cookies per hop and across origins, timings, TLS configuration errors |
| `test/features/http/http2_engine_test.dart` | HTTP/2 end to end (skipped when the platform's Dart TLS server cannot negotiate ALPN), HTTP/1.1 fallback, custom CA, mutual TLS |
| `test/features/workspace_features_test.dart` | tab reordering, session restore, inheritance through the cubits, folder secrets, duplicate/delete/export/import, bulk actions, cookies and templates in SQLite, migration v1 to v2, runner iterations, workspace registry |
| `test/features/run_data_and_shortcuts_test.dart` | CSV/JSON run data, shortcut parsing and conflicts |
| `test/core/json_path_test.dart` | JSONPath builder |

`test/fixtures` needs no setup; the HTTP/2 tests skip themselves (reported as skipped) when ALPN is unavailable.

### What was run for 0.4.0 and how

The environment that wrote this release had no Flutter SDK. A plain Dart SDK, the real `sqlite3` and `http2` packages and a small shim for `flutter_test` were used to run every non-widget test file: 261 tests passed, 0 failed, 5 skipped (HTTP/2 end-to-end tests, because that Dart build cannot negotiate ALPN on the server side). The HTTP/2 client path was also exercised with a Python TLS terminator in front of a Dart HTTP/2 server (GET, POST body, size limit, certificate rejection, custom CA, cancellation, cookies). `dart analyze` with the project's lint rules over all of `lib/` and the non-widget tests reported no issues, using real Flutter 3.35.7 sources; the only exceptions were the `flutter_localizations` import in `app.dart`, which could not be resolved there. **Not run:** `flutter test` itself, any widget test (`test/ui/*`), any platform build, anything on a device.


## 1.0.0 tests

New or changed: `test/features/settings_test.dart` (new defaults, schema 2 migration), `test/core/html_util_test.dart` (title, image detection, link policy), and four widget tests in `test/ui/widgets_test.dart` (two-pane settings, phone settings hub, splash) that were written but **not run**. Run total in the build environment: 268 passed, 0 failed, 5 skipped (non-widget tests only).
