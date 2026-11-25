# Changelog

## 1.0.0

- New logo (`assets/branding/logo.png`) used everywhere: splash, header, menu, About, onboarding, launcher icons, Windows installer, Linux packages
- Splash screen (in-app on all platforms, native on Android)
- Persian digits by default in every language (new `PostBoxDigits` font); dark theme by default; onboarding offers dark, light or system with previews. Settings saved by earlier versions move to these defaults once and show the first-run screen again
- Settings split into eight groups (two-pane on wide windows, one page per group on phones)
- Redesigned header: desktop (logo, workspace chip, search field with shortcut, environment, import/export, theme toggle, settings) and phone app bar
- HTML responses open as a browser-like page (address bar, title, rendered page); static renderer, no JavaScript, images blocked until allowed, links open only after confirmation
- Version is 1.0.0 (build 5); the 0.4.0 entries below are part of this release
- Update check: on start-up PostBox asks the GitHub releases of `ghaderi0x/PostBox` for the newest version (switch in Settings > About) and shows an update card with the release notes. Windows and Linux download the installer inside the app and check it against `SHA256SUMS.txt`; Android opens Myket or Bazaar. "Later" and "Skip this version" are available
- Windows and Linux: new two-pane Settings (arrow keys, Esc) and a two-column first-run tour (arrow keys, Enter, Esc); the keyboard shortcut guide is hidden on phones
- New charts: timing waterfall in the response timeline, pass/fail and slowest requests in the runner, and an Insights page built from history
- Short toasts everywhere; on Windows and Linux they are a compact card in the corner
- Every `InkWell` replaced by a `GestureDetector`-based `Pressable` (cursor, hover and pressed tint)
- Fixed line numbers overflowing in Persian layout (raw and pretty response)
- Windows: window border follows the accent colour
- Light/dark schedule: Settings > Appearance can switch to the dark theme between two times (for example 19:00 to 07:00); using the header theme button turns it off
- Desktop header: tinted with the accent colour, and on Windows the native title bar follows it (Windows 11 colours it, Windows 10 switches light/dark; needs `tool/apply_windows_titlebar.sh`). New Menu button in the header opens the same list as the phone Menu tab (Insights, Environments, Cookies, Templates, Runner, Language, Tour ...)
- Response, Request and Runner pages scroll as one page: the status row, URL bar, tab bar or settings block scroll away with the content and return when you scroll up
- Credit line and GitHub link in Settings > About and on the desktop tour
- Release tooling: tag-driven GitHub Actions release for Windows, Linux and macOS (installer, `.dmg`, `.deb`, AppImage), `tool/bump_version.sh`, checksum file
- macOS support: runner setup with sandbox entitlements, `.dmg` packaging, in-app update for macOS
- New README (English and Persian) with banner and demo slot; privacy policy and in-app privacy text now mention the optional update check

## 0.4.0 (unreleased)

- Fonts bundled: Vazirmatn (Persian UI), Inter (English UI), JetBrains Mono (code), with their OFL licences
- Draggable tabs; configurable keyboard shortcuts; tabs, drafts and panel layout restored on start
- Native file dialogs and drag-and-drop of files onto the window (import preview); Android share / open-with bridge
- Binary request body from a file; load and save request bodies; JSON tree view with copy value / copy path
- Cookie jar (persistent, RFC 6265 style) with a manager page; HTTP/2 (opt-in, ALPN); timeline tab with timings, protocol and server certificate; mutual TLS and extra CA certificates
- Inherited auth and headers, folder/collection settings, folder and request variables with a resolution inspector
- PostBox Script: sandboxed pre-request and post-response scripts (never imported from files)
- Multiple workspaces (one database file each); request templates; bulk delete, move and export; bulk edit for headers, params and variables
- Runner: iterations, parallel iterations and CSV/JSON data files
- Fixes found by new tests: nested database transactions now join the outer one; cookie `Domain` can no longer suffix-match an IP address
- `docs/COMPETITOR_RESEARCH.md`, `docs/SCRIPTING.md`; feature matrix: no item left "Missing" (see the file for what is partial or declined)

## 0.3.0 (unreleased)

- New visual language: rounded soft cards, floating navigation bar, grouped Menu tab, gradient CTA, pill tabs
- Welcome tour (language, theme, optional sample collection), re-openable from Settings and Menu
- `docs/FEATURE_MATRIX.md`: comparison with the master TODO list

## 0.2.0

- HTTP engine with explicit redirect policy, proxy, TLS validation, size limits, cancellation
- Request workspace, response inspector (pretty/raw/diff), custom code editor
- Collections, history, environments, secrets in secure storage
- Basic, Bearer, API key, OAuth 2.0 Authorization Code + PKCE
- Import/export: cURL, Postman v2.1, PostBox, OpenAPI JSON
- Assertions, chaining, collection runner, SSE, WebSocket, GraphQL
- Six themes, English and Persian (RTL), full settings
- Not yet compiled or run; see `docs/PROJECT_STATUS.md`

## 0.1.0

- Initial scaffold
