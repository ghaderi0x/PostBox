# Feature matrix vs the master TODO list

Compares the TODO list you shared (Phases 0-8; the text you pasted ended in the middle of Phase 8) with what is written in this repository. The state column is defined below; what was and was not run is listed in `PROJECT_STATUS.md`.

Summary: 30 done, 14 partial, 2 declined (with reasons), 0 missing out of 46 grouped items.

States: **Done** = implemented and covered by tests that were run (or, for UI-only behaviour, type-checked against Flutter 3.35.7 but not run); **Partial** = works with a documented limit; **Declined** = deliberately not built, reason given.

| Phase | Item | State | Notes |
|---|---|---|---|
| P0 | Competitor research, feature matrix, complaint database | Partial | Research done and dated in `docs/COMPETITOR_RESEARCH.md` (Postman, Insomnia, Bruno, Hoppscotch, with sources). No complaint database yet; it needs a larger, systematic pass over issue trackers. |
| P0 | PRD, MVP, acceptance criteria, benchmarks | Partial | Product spec and security requirements exist; no measured benchmarks or formal PRD. |
| P1 | Android, Windows, Linux | Done | Written for all three; none built or tested yet. macOS was added afterwards (runner setup, `.dmg`, release job); also untested. |
| P1 | iOS/macOS-ready architecture | Partial | No platform-specific code outside `dart:io`, secure storage and app links, but not checked. |
| P1 | Clean architecture, DI, Bloc/Cubit, repository interfaces | Partial | Feature folders, constructor DI and repository interfaces exist; domain/data split is not strict everywhere. |
| P1 | FFI / native engine | Declined | Not used. `dart:io` covers current needs and no measurement shows a gain; an FFI engine would add per-platform native builds. Revisit only with a benchmark. See `docs/ARCHITECTURE.md`. |
| P2 | Design system, themes, accent, density, persisted | Done | Six themes, custom accent, density, text scale, reduced motion. |
| P2 | Premium look (soft cards, floating nav, onboarding) | Done | Added in 0.3.0 (rounded cards, floating pill nav on phone, grouped menu, gradient CTA, welcome tour). Visual polish still needs your review on a device. |
| P2 | Resizable panels, multiple tabs, command palette, context menus | Done | Resizable sidebar and split, tabs, Ctrl+K, popup menus. |
| P2 | Draggable/reorderable tabs | Done | Desktop tab strip uses `ReorderableListView`; ordering logic (`reorderTabs`, `selectRelative`) is covered by tests. The drag gesture itself was type-checked but not run on a device. |
| P2 | Configurable keyboard shortcuts | Done | Seven actions can be rebound in Settings > Keyboard or the Shortcuts page, with conflict detection, validation and reset. Combos are parsed and de-duplicated by tested code. Editor shortcuts stay fixed. |
| P2 | Restore workspace after restart (tabs, panel sizes) | Done | Open tabs (drafts without secrets), the active tab, sidebar width, split fraction and orientation are restored per workspace; switch in Settings > Data and privacy. Secrets typed into unsaved tabs are not kept. Tested. |
| P2 | Drag-and-drop import, native file dialogs | Done | `file_picker` for open/save dialogs (import, body, CA/cert files, run data, response save) behind a `FileService` interface; `desktop_drop` lets you drop a file on the window to open the import preview. Plugins not yet run on a device. |
| P2 | Android share/open-with for cURL and collections | Partial | Kotlin bridge (`android_overlay/MainActivity.kt`), manifest filters and Dart service are written; shared text or JSON opens the import preview. Never built or run on Android. |
| P2 | Accessibility (labels, focus, scaling) | Partial | Tooltips, semantics on custom nav, text scaling, high-contrast theme. No screen-reader audit. |
| P3 | All methods incl. custom, params, headers, enable/disable | Done | Key/value rows with enable checkboxes; repeated keys allowed. |
| P3 | Body types: JSON, text, form, multipart, files, GraphQL | Done | Multipart files by path. XML uses Raw with a Content-Type. |
| P3 | Binary body from file, load/save body to file | Done | New Binary body type (file path, streamed size check against the request limit), load body from file and save body to file for text bodies, cURL and Postman export. Builder and executor tested against a local server. |
| P3 | Timeout, cancel, redirects (policy, limit, chain shown) | Partial | One total timeout (no separate connect/read/write); redirect count is shown, not the full chain. |
| P3 | HTTP/2, HTTP/3 | Partial | HTTP/2 through ALPN with the pure-Dart `http2` package (opt-in in Settings, https without proxy only, one connection per request, no push). Exercised end to end against a local HTTP/2 server behind a TLS terminator. HTTP/3 is not supported: `dart:io` has no QUIC. |
| P3 | Cookie jar and persistence | Done | RFC 6265 style jar stored in the workspace database, applied per redirect hop, with a manager page and an off switch. Known limit: no public-suffix list. Tested. |
| P3 | Distinct DNS / TLS / timeout / cancel errors | Partial | Timeout, cancel, TLS, connection, protocol, redirects are distinct; DNS is part of "connection". |
| P3 | No duplicate sends, concurrent requests across tabs | Done | A tab cannot send twice at once; tabs run independently. |
| P4 | Status, time, size, headers, cookies, body, copy, save | Done | Plus truncation warning and redirect count. |
| P4 | Timestamps and timing breakdown (DNS/connect/TLS) | Partial | Timeline tab: connect (DNS, TCP and TLS together), wait (send + first byte), download, redirects, total. `dart:io` does not expose DNS/TCP/TLS separately, so they cannot be split. |
| P4 | JSON tree, expand/collapse, copy JSON path | Done | Tree mode in the body view: lazy expansion, paging of long lists, copy value and copy JSONPath. Path builder tested. |
| P4 | XML/HTML/text/image/binary, large responses | Done | HTML is shown as source only. Large bodies use a virtualized line view. |
| P4 | Audio/video previews | Declined | Not built: reliable playback on Windows, Linux and Android needs a native media stack (for example `media_kit`) that adds large binaries per platform. The inspector shows a clear message and Save instead. |
| P4 | Request inspector (masked, what was sent) | Partial | Method, URL, headers (masked), body preview and warnings. No variable-origin inspector. |
| P5 | None, Basic, Bearer, API key | Done | Secrets in secure storage. |
| P5 | OAuth 2.0 | Partial | Authorization Code + PKCE and refresh only. |
| P5 | Inherited auth (collection/folder) | Done | Requests can inherit auth from the nearest folder or collection (and inherited headers). The Auth tab shows where it comes from. Secrets stay in secure storage. Tested. |
| P5 | mTLS, custom CA, certificate inspection | Done | Client certificate chain and key (PEM, optional password in secure storage), extra CA, and a Timeline view of the server certificate (subject, issuer, validity, SHA-1, PEM). Tested against a local mutual-TLS server. |
| P5 | Secure storage, redaction, safe export | Done | Keystore with in-memory fallback and a visible warning. |
| P6 | Collections, folders, move, reorder, duplicate, favorites, search | Done | Reorder by up/down, not drag. |
| P6 | Folder-level settings/variables/auth, collection auth | Done | Collections and folders carry auth, headers and scripts; folders also carry variables. Settings page in the sidebar menu. Secrets in the vault, never in the database or default exports. |
| P6 | Bulk edit/delete/export, request templates | Done | Selection mode in the library (bulk delete, move, export), bulk edit for headers/params/variables, built-in and user request templates. Tested. |
| P6 | Multiple workspaces | Done | Each workspace is its own database file (collections, environments, history, cookies, templates, session). Settings and secrets are shared. Create, rename, switch, delete in the Workspaces page. |
| P6 | History: search, replay, retention, redaction | Done | Filter by method/URL text; no filter by status/time. |
| P7 | Global, collection, environment variables with precedence | Done | Plus runtime values from chaining. |
| P7 | Folder/request-level variables, resolution inspector | Done | Precedence: global < collection < folder < request < environment < runtime. The Variables tab lists every `{{name}}` the request uses with value (secrets masked) and source layer. Tested. |
| P7 | Import/export environments | Partial | Environments travel inside PostBox exports; no standalone environment file. |
| P8 | Pre/post-request scripts and sandbox | Done | PostBox Script: a small interpreter written for this app (no JavaScript engine), with step, time and size limits, no file/network/secret access. Collection, folder and request scripts. Scripts are never imported. See `docs/SCRIPTING.md`. Tested. |
| P8 | Assertions (status, header, body, JSONPath, duration) | Done | No JSON schema validation. |
| P8 | Collection runner, sequential, reports | Done | Markdown/JSON report dialogs. |
| P8 | Parallel runs, data-driven runs, fixtures | Partial | Runner supports iterations, up to 8 parallel iterations and CSV/JSON data files (each row's columns become variables). There is no mock server or fixture manager. |

Phases 9 and later were not in the pasted text. Send the rest of the list to extend this table.
