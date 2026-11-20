# Third-party notices

PostBox's own code is MIT licensed (see `LICENSE`).

Packages used at runtime (licences as published on pub.dev; verify with `flutter pub deps` and the in-app licence page, which lists every dependency's full text automatically via Flutter's `LicenseRegistry`):

| Package | Licence (expected) |
|---|---|
| flutter, flutter_localizations | BSD-3-Clause |
| flutter_bloc | MIT |
| shared_preferences, path_provider, url_launcher | BSD-3-Clause |
| path, crypto | BSD-3-Clause |
| sqlite3 (and the bundled SQLite, public domain) | MIT |
| flutter_secure_storage | BSD-3-Clause |
| app_links | Apache-2.0 / BSD (check package page) |
| http2 | BSD-3-Clause (checked in the package repository) |
| flutter_widget_from_html_core | MIT (checked in the package repository) |
| flutter_launcher_icons, flutter_native_splash (dev only) | MIT (check the package pages) |
| file_picker, desktop_drop | MIT (expected; check the package pages before release) |

Fonts (bundled in `assets/fonts`, all SIL Open Font License 1.1; the licence texts are next to the files): Inter 4.1 (`OFL-Inter.txt`), Vazirmatn (`OFL-Vazirmatn.txt`), JetBrains Mono 2.304 (`OFL-JetBrainsMono.txt`).

Before a release, regenerate this list from the lockfile and confirm each licence.
