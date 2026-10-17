# Architecture

## Structure
Feature-oriented: `lib/core/` (design, shared utilities) and `lib/features/<feature>/{domain,data,presentation}`. State: Bloc/Cubit with constructor injection (no service locator).

## Decisions
- **HTTP:** `HttpEngine` interface (`features/http/domain`), implemented by `IoHttpEngine` on `dart:io` `HttpClient`. Redirects are followed manually to enforce an explicit policy; Authorization, Cookie and Proxy-Authorization are dropped on cross-origin redirects. Responses are read as a stream with a byte limit.
- **Persistence:** Drift (SQLite), versioned migrations, transactions. SQLCipher evaluated later.
- **Secrets:** `flutter_secure_storage`; Linux needs libsecret and absence must degrade gracefully.
- **Design:** semantic tokens in a `ThemeExtension` (`PostBoxColors`).

## Reversible assumptions
- Latin digits by default; optional Persian digits and Jalali dates setting.
- No cloud sync in v1. No telemetry.
- Package versions in `pubspec.yaml` are caret ranges chosen without network access and must be verified with `flutter pub get` before the first commit of `pubspec.lock`.

## Dependency practice
Pin through the committed lockfile; review licences and maintenance before adding a package; update deliberately, one at a time, with tests.
