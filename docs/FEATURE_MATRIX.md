# Feature matrix vs the master TODO list

Compares the TODO list you shared (Phases 0-8; the text you pasted ended in the middle of Phase 8) with what is written in this repository. "Done" means written, not verified by running (see `PROJECT_STATUS.md`).

Summary: 16 done, 9 partial, 21 missing out of 46 grouped items.

| Phase | Item | State | Notes |
|---|---|---|---|
| P0 | Competitor research, feature matrix, complaint database | Missing | Not started. Needs a dedicated research pass with sources and dates. |
| P0 | PRD, MVP, acceptance criteria, benchmarks | Partial | Product spec and security requirements exist; no measured benchmarks or formal PRD. |
| P1 | Android, Windows, Linux | Done | Written for all three; none built or tested yet. |
| P1 | iOS/macOS-ready architecture | Partial | No platform-specific code outside `dart:io`, secure storage and app links, but not checked. |
| P1 | Clean architecture, DI, Bloc/Cubit, repository interfaces | Partial | Feature folders, constructor DI and repository interfaces exist; domain/data split is not strict everywhere. |
| P1 | FFI / native engine | Missing | Not used. No measurable benefit has been shown yet; `dart:io` covers current needs. |
| P2 | Design system, themes, accent, density, persisted | Done | Six themes, custom accent, density, text scale, reduced motion. |
| P2 | Premium look (soft cards, floating nav, onboarding) | Done | Added in 0.3.0 (rounded cards, floating pill nav on phone, grouped menu, gradient CTA, welcome tour). Visual polish still needs your review on a device. |
| P2 | Resizable panels, multiple tabs, command palette, context menus | Done | Resizable sidebar and split, tabs, Ctrl+K, popup menus. |
| P2 | Draggable/reorderable tabs | Missing | Tabs cannot be dragged or reordered. |
| P2 | Configurable keyboard shortcuts | Missing | Shortcuts are fixed and listed in Settings. |
| P2 | Restore workspace after restart (tabs, panel sizes) | Missing | Open tabs and panel sizes are not persisted. Saved requests are. |
| P2 | Drag-and-drop import, native file dialogs | Missing | No file-picker dependency yet. Import uses a typed path or pasted text. |
| P2 | Android share/open-with for cURL and collections | Missing | Not implemented. |
| P2 | Accessibility (labels, focus, scaling) | Partial | Tooltips, semantics on custom nav, text scaling, high-contrast theme. No screen-reader audit. |
| P3 | All methods incl. custom, params, headers, enable/disable | Done | Key/value rows with enable checkboxes; repeated keys allowed. |
| P3 | Body types: JSON, text, form, multipart, files, GraphQL | Done | Multipart files by path. XML uses Raw with a Content-Type. |
| P3 | Binary body from file, load/save body to file | Missing | Not implemented. |
| P3 | Timeout, cancel, redirects (policy, limit, chain shown) | Partial | One total timeout (no separate connect/read/write); redirect count is shown, not the full chain. |
| P3 | HTTP/2, HTTP/3 | Missing | `dart:io` HttpClient speaks HTTP/1.1 only. |
| P3 | Cookie jar and persistence | Missing | Cookies are shown but not stored or re-sent. |
| P3 | Distinct DNS / TLS / timeout / cancel errors | Partial | Timeout, cancel, TLS, connection, protocol, redirects are distinct; DNS is part of "connection". |
| P3 | No duplicate sends, concurrent requests across tabs | Done | A tab cannot send twice at once; tabs run independently. |
| P4 | Status, time, size, headers, cookies, body, copy, save | Done | Plus truncation warning and redirect count. |
| P4 | Timestamps and timing breakdown (DNS/connect/TLS) | Missing | Only total duration. |
| P4 | JSON tree, expand/collapse, copy JSON path | Missing | Pretty/raw views with find; no tree. |
| P4 | XML/HTML/text/image/binary, large responses | Done | HTML is shown as source only. Large bodies use a virtualized line view. |
| P4 | Audio/video previews | Missing | Not implemented. |
| P4 | Request inspector (masked, what was sent) | Partial | Method, URL, headers (masked), body preview and warnings. No variable-origin inspector. |
| P5 | None, Basic, Bearer, API key | Done | Secrets in secure storage. |
| P5 | OAuth 2.0 | Partial | Authorization Code + PKCE and refresh only. |
| P5 | Inherited auth (collection/folder) | Missing | Auth is per request. |
| P5 | mTLS, custom CA, certificate inspection | Missing | Not implemented. |
| P5 | Secure storage, redaction, safe export | Done | Keystore with in-memory fallback and a visible warning. |
| P6 | Collections, folders, move, reorder, duplicate, favorites, search | Done | Reorder by up/down, not drag. |
| P6 | Folder-level settings/variables/auth, collection auth | Missing | Collections have variables only. |
| P6 | Bulk edit/delete/export, request templates | Missing | Not implemented. |
| P6 | Multiple workspaces | Missing | One local workspace. Clear-all exists. |
| P6 | History: search, replay, retention, redaction | Done | Filter by method/URL text; no filter by status/time. |
| P7 | Global, collection, environment variables with precedence | Done | Plus runtime values from chaining. |
| P7 | Folder/request-level variables, resolution inspector | Missing | Unresolved variables are warned about; origin is not shown. |
| P7 | Import/export environments | Partial | Environments travel inside PostBox exports; no standalone environment file. |
| P8 | Pre/post-request scripts and sandbox | Missing | Deliberately not built until a sandbox is chosen. |
| P8 | Assertions (status, header, body, JSONPath, duration) | Done | No JSON schema validation. |
| P8 | Collection runner, sequential, reports | Done | Markdown/JSON report dialogs. |
| P8 | Parallel runs, data-driven runs, fixtures | Missing | Not implemented. |

Phases 9 and later were not in the pasted text. Send the rest of the list to extend this table.
