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
