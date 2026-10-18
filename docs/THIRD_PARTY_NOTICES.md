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

Fonts (not yet bundled; all SIL Open Font License 1.1, copyright lines must accompany the files): Inter, Vazirmatn, JetBrains Mono.

Before a release, regenerate this list from the lockfile and confirm each licence.
