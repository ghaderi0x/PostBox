# Contributing

Thanks for helping. Please keep changes small and tested.

1. Run `./tool/setup_platforms.sh` once, then `flutter pub get`.
2. Before a pull request: `dart format .`, `flutter analyze`, `flutter test` must pass.
3. Do not add a setting that has no effect, a placeholder screen or a dead button.
4. Never log or commit secrets, tokens or personal data. Redaction helpers are in `lib/core/util/redact.dart`.
5. New user-facing text goes into both `lib/l10n/strings_en.dart` and `strings_fa.dart` with identical keys and placeholders (a test checks it).
6. Update the docs in `docs/` and `docs/fa/` when behaviour changes, and keep `docs/PROJECT_STATUS.md` truthful: say what you ran and what you saw.
7. New dependencies need a reason, a licence check and a platform check.

By contributing you agree your work is released under the MIT licence.
