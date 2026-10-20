# Project Status

Updated at the end of the first full build session (2026-10-18).

## The honest summary

All nine phases were **written**. **None of it has been compiled or run.** The environment used to write it had no Flutter or Dart SDK and no network for the shell. Therefore:

- `dart format`, `flutter analyze`, `flutter test` and every platform build were **not run**.
- Expect compile errors and some failing tests on the first run. The code was reviewed by hand against the Flutter/Dart APIs, but a compiler has not seen it.
- No screenshots exist. No platform was built. Nothing was tested on a device.

## What was actually run in this session

| Check | Result |
|---|---|
| Python script: WCAG contrast of all theme colours | all required pairs >= 4.5:1 (worst semantic colour 4.64:1) |
| Python script: Gregorian to Jalali algorithm vs known dates | matches (2026-10-17 = 1405/07/25, 2024-01-01 = 1402/10/11, 2026-03-21 = 1405/01/01) |
| Script: bracket/brace balance and import-path existence for every `lib/` file | no problems |
| Script: every localization key used in `lib/ui` and `lib/app` exists in both languages | 440 keys, none missing |
| Web search: Google Play target API requirement | targetSdk 36 required by 2026-08-31 for new apps/updates (re-check in Play Console) |
| Web search: package state | `sqlite3` is at 3.x with native assets (no `sqlite3_flutter_libs`); `flutter_secure_storage` Linux plugin 3.x; Play API level above |

## Phase table

| Phase | Written | Verified |
|---|---|---|
| P0 docs (EN + FA), CI, scaffold | yes | no |
| P1 design system, 6 themes, EN/FA localization, settings, logo | yes (fonts/icons not bundled) | contrast only |
| P2 HTTP engine | yes | no |
| P3 workspace, inspector, custom editor | yes | no |
| P4 SQLite persistence, collections, history | yes (sqlite3, not Drift) | no |
| P5 environments, secrets, redaction | yes | no |
| P6 auth + OAuth 2.0 PKCE | yes | no |
| P7 import/export | yes | no |
| P8 assertions, chaining, runner, SSE, WebSocket, GraphQL, OpenAPI JSON, diff, palette | yes | no |
| P9 release scripts and docs | yes (nothing built, nothing signed) | no |

## Platforms

| Platform | Built here | Notes |
|---|---|---|
| Android | **no** | needs `tool/setup_platforms.sh`, Gradle edits and a keystore (`docs/RELEASE.md`) |
| Windows | **no** | must be built on Windows; Inno Setup script in `packaging/` |
| Linux | **no** | must be built on Linux; needs `libsecret-1-dev`; `.deb` and AppImage scripts in `packaging/` |

Do not describe any platform as ready until it was built and tested.

## First-run checklist

1. `./tool/setup_platforms.sh` (generates runner projects, removes the template widget test, patches the Android manifest).
2. `flutter pub get` and commit `pubspec.lock`. If a version range does not resolve, adjust it and note it here.
3. `dart format .`, `flutter analyze`, `flutter test`. Fix errors in this order: compile errors, analyzer warnings, failing tests.
4. Run on desktop and look at every screen in light/dark and English/Persian; adjust overflow and spacing.
5. Bundle fonts and icons.
6. Record exact results in this file.

## Known risks and unresolved items

- Package APIs were written from memory plus changelogs: `sqlite3` 3.x, `flutter_secure_storage` 10.x, `app_links` 6.x. Small API mismatches are likely.
- Flutter API drift: the code uses `DropdownButtonFormField.initialValue` (needs Flutter 3.35+), `WidgetStateProperty`, `Color.withAlpha`.
- The editor's behaviour with real IMEs, selection and RTL text is untested by hand.
- Widget tests that tap through the app may need selector tweaks.
- Android OAuth redirect relies on the intent filter added by the setup script and on `app_links`; untested on a device.
- App icons and fonts are missing; the logo is a simple original placeholder.
- Test files contain a few lines that `dart format` will rewrite; run the formatter before committing.

## Field reports

- 2026-10-19: `flutter pub get` resolved cleanly (`app_links` 6.4.1, `flutter_secure_storage` 10.3.4). A release APK installed on an Android phone started and showed the startup error screen with `NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll`. Likely cause: R8 shrinking in the release build. Mitigation added: keep rules + `android.enableR8.fullMode=false` (see `docs/RELEASE.md`). Not yet confirmed fixed.

## Version 0.3.0 (UI refresh)

Added after the first device test: soft rounded cards, floating pill navigation with an expanding selected item (phone), a Menu tab with grouped icon rows, gradient primary button, pill tabs, welcome tour with optional sample collection, softer theme (rounded inputs, buttons, sheets, menus). All of it is **written, not yet run**; check it on your phone. See `FEATURE_MATRIX.md` for the comparison with your TODO list.

## Deviations from the brief

- sqlite3 instead of Drift (see `ARCHITECTURE.md`).
- Scripts sandbox, request comparison and shortcut customization are not implemented (see `PRODUCT_SPEC.md`).
- Fonts and platform icons are not bundled.

## Next actions

See `ROADMAP.md`. Resume from the first-run checklist above.
