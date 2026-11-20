# Fonts

PostBox bundles three open fonts, all under the SIL Open Font License 1.1. The licence text of each is next to its files.

| Role | Family (in `pubspec.yaml`) | Version | Files | Source |
|---|---|---|---|---|
| Persian UI text | Vazirmatn | repository master at bundling time | Regular, Medium, SemiBold | https://github.com/rastikerdar/vazirmatn |
| English UI | Inter | 4.1 | Regular, Medium, SemiBold | https://github.com/rsms/inter |
| Numbers in UI text | PostBoxDigits | derived | Regular, Medium, SemiBold, Bold | Ten glyphs taken from Vazirmatn (Persian digit shapes mapped onto 0-9). Licence: Vazirmatn's OFL; the font was renamed. |
| Code, URLs, JSON | JetBrainsMono | 2.304 | Regular, Bold | https://github.com/JetBrains/JetBrainsMono |

How they are used (`lib/core/design/theme.dart`): with a Persian UI language Vazirmatn is the primary font and Inter the fallback; with English, Inter is primary and Vazirmatn is the fallback, so Persian text inside an English UI still renders in Vazirmatn. Code uses JetBrains Mono with Vazirmatn as its first fallback for Persian strings inside code.

Static `.ttf` files are used (not variable fonts) so weights map to the `weight:` entries in `pubspec.yaml`. To update a font, replace the files, keep the file names, and update the version above.
