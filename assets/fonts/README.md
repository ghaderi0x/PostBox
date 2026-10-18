# Fonts

PostBox uses three open fonts, all under the SIL Open Font License 1.1:

| Role | Family | Source |
|---|---|---|
| Persian text | Vazirmatn | https://github.com/rastikerdar/vazirmatn |
| English UI | Inter | https://rsms.me/inter/ |
| Code, URLs | JetBrains Mono | https://www.jetbrains.com/lp/mono/ |

The font files are **not** committed (they could not be downloaded when this
repository was generated). To bundle them:

1. Download the static `.ttf` files for the weights listed in `pubspec.yaml`.
2. Copy them here, keeping the file names used in the commented block.
3. Uncomment the `fonts:` block in `pubspec.yaml`.
4. Add each font's licence text next to it (`OFL-Inter.txt`, ...) and keep the
   copyright lines; `docs/THIRD_PARTY_NOTICES.md` lists what to include.

Until then the app falls back to the platform default fonts. Persian text still
renders correctly with system fonts, only the look differs.
