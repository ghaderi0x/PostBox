# Architecture

## Layout

```
lib/
  app/            composition root (services.dart) and the MaterialApp (app.dart)
  core/           design tokens/themes, util (ids, redaction, formatting, jalali, log), shared models
  features/
    http/         HttpEngine interface, IoHttpEngine (dart:io), request builder, executor
    requests/     RequestModel, AuthConfig
    environments/ variables, resolver, repository, cubit
    collections/  records, repository (SQLite), cubit
    history/      entries, repository, cubit
    workspace/    WorkspaceCubit: tabs, send, SSE/WebSocket sessions
    runner/       RunnerCubit
    auth/         OAuth 2.0 + PKCE service
    streaming/    SSE and WebSocket sessions
    testing/      assertions, extractions, JSONPath, line diff
    import_export/ cURL, Postman, PostBox, OpenAPI
    persistence/  AppDatabase (migrations, transactions)
    secrets/      SecretStore, SecretVault
    settings/     AppSettings, repository, cubit
    data/         "clear local data"
  l10n/           hand-written EN/FA tables
  ui/             screens and widgets; ui/editor is the custom editor
```

Dependencies are injected through constructors. `AppServices` is the only place that wires concrete classes. Cubits receive other cubits explicitly (for example `WorkspaceCubit` gets `CollectionsCubit`, `EnvironmentsCubit`, `HistoryCubit`).

## Key decisions

| Decision | Reason |
|---|---|
| `dart:io` `HttpClient` behind `HttpEngine` | Full control of TLS, proxy, cancellation, streaming. Redirects are followed by hand so the policy is explicit and testable. |
| **`package:sqlite3` instead of Drift** | Drift needs `build_runner` code generation, which could not be run when this code was written, and hand-writing generated code would be fragile. The data layer is a thin set of repositories over `sqlite3` with `PRAGMA user_version` migrations and explicit transactions. The repository interfaces keep a later move to Drift local. **This deviates from the original brief and is reversible.** |
| Repositories are synchronous | `sqlite3` is synchronous and the data is small. A later move to an isolate would only change the repositories. |
| Secrets in `flutter_secure_storage` via `SecretVault` | The database and exports only see the non-secret half of models. If the keystore is unavailable the store degrades to memory and the UI says so. |
| Hand-written localization | No `gen_l10n` step. A test enforces identical keys and placeholders in English and Persian. |
| Bloc/Cubit | As decided. State classes are plain immutable classes; every change emits a new instance. |

## Variable precedence (highest first)

1. Runtime overlay (values extracted by chaining during a runner run)
2. Active environment
3. Collection variables
4. Global variables

Chaining outside the runner writes extracted values into the active environment (or globals when none is active) as ordinary, non-secret variables.

## Reversible assumptions

- Latin digits by default; Settings can switch to Persian digits and Jalali dates.
- No cloud sync in v1; no telemetry.
- Package versions in `pubspec.yaml` were chosen from pub.dev changelogs on 2026-10-18 without running `flutter pub get`. Treat the first resolution as part of verification.

## Dependency update practice

Commit `pubspec.lock`. Update one package at a time, read its changelog, run format, analyze and tests, and re-check licences and platform support. Prefer fewer packages: this app currently uses ten runtime packages.


## 0.4.0 additions

### Inheritance and variables

Collections and folders carry `NodeSettings` (auth, headers, scripts; folders also variables), stored as JSON in a `settings_json` column (migration v2). Secrets of those levels live in the secret vault under `node.<id>.<field>` and `var.<id>`, never in the database row. `InheritanceResolver` merges the chain collection > folders for a request: the innermost defined auth wins (`AuthType.inherit` means "ask the parent", `none` means "explicitly no auth"), inherited headers sit under the request's own headers (same name: the request wins, inner level beats outer), scripts run outermost first before and innermost first after.

Variable precedence, lowest to highest: global, collection, folder (inner wins), request, active environment, runtime values (extractions, scripts, runner data). The environment deliberately beats the whole collection tree so one collection can run against several environments.

### HTTP

`IoHttpEngine` stays on `dart:io`. Per hop it builds the Cookie header from the jar (so cookies never follow a redirect to another host), sends over HTTP/1.1, or over HTTP/2 when the setting is on, the URL is https and no proxy is configured. HTTP/2 uses the pure-Dart `http2` package on a `SecureSocket` with ALPN; if the server does not pick `h2` the request falls back to HTTP/1.1 on a new connection. Limits: one connection per request, no push, no connection reuse. Custom CA and client certificates use a `SecurityContext`; files that cannot be read or parsed become a `tls` failure with a clear message. Timings: connect (DNS + TCP + TLS together), wait, download, earlier redirect hops.

### Declined, with reasons

- **FFI / native engine**: no measured need; it would add per-platform native builds.
- **HTTP/3**: `dart:io` has no QUIC; a third-party native library would be required.
- **Audio/video preview**: needs a native media stack on three platforms; the inspector says so and offers Save.

### Workspaces and session

A workspace is one SQLite file (`postbox.db` for the default, `ws_<id>.db` for others) listed in a small registry in shared preferences. Switching workspaces builds new services and rebuilds the app under `PostBoxRoot`. Settings and secrets are shared by all workspaces. Tabs (drafts without secrets) and layout are stored in the workspace database (`kv`) and restored on start when the setting is on.

### Scripts

`features/scripting` is a hand-written lexer, parser and tree-walking interpreter with step, time and size limits. Host objects expose only what `docs/SCRIPTING.md` lists. No JavaScript engine is embedded: it would add a native dependency on every platform and a larger attack surface.

### Platform edges

`FileService` hides `file_picker`; `ShareIntentService` talks to `android_overlay/MainActivity.kt` over a MethodChannel; `desktop_drop` is wrapped in the app shell and switched off in widget tests (`AppServices.enableFileDrop`).

### Reversible assumptions

Default HTTP version is HTTP/1.1 (HTTP/2 is opt-in); cookies are stored in plain text in the local database (they are server-issued session ids, removed by Clear local data); deleting a workspace deletes its database file but not its entries in the system secure storage.
