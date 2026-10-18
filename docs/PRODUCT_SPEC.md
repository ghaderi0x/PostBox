# PostBox Product Specification

PostBox is an open-source, local-first HTTP API client by Uniqueone (MIT). It needs no account, backend or internet connection for local workflows, and the core client never depends on an external AI service.

**Platforms:** Android, Windows, Linux. **Languages:** English (LTR) and Persian (real RTL). **Application ID:** `com.uniqueone.postbox`.

> Status vocabulary used in all docs: **Written** = code exists in this repository; **Verified** = it was run and the result was seen. At the time of this document **nothing is Verified** (see `PROJECT_STATUS.md`).

## Feature scope and state

| Area | What exists | State |
|---|---|---|
| HTTP engine | All methods incl. custom, timeout, cancel, manual redirect policy (never / same origin / always) with sensitive-header stripping across origins, proxy (`host:port`), TLS validation on by default, response size limit with truncation flag, request size limit, no automatic retries | Written + tests |
| Request workspace | Tabs, URL bar, params, headers, body types (none, JSON, text, form URL-encoded, multipart, raw, GraphQL), auth, tests, info, send/cancel, draft vs saved state (dirty marker) | Written |
| Response inspector | Pretty/Raw/Diff body, headers, cookies (values hidden until revealed), tests, request preview (secrets masked), status/time/size, save to file, image view, hex preview for binary, large responses as virtualized lines, HTML shown as source only | Written |
| Custom editor | Highlighting (JSON, XML/HTML, variables), line numbers, wrap toggle, auto-indent, bracket match + auto-close, find/replace with regex, go to line, undo/redo, JSON format/minify, inline JSON error markers | Written (see `EDITOR.md` for limits) |
| Collections | Collections, nested folders, saved requests, duplicate, rename, move, reorder (up/down), delete, descriptions, favorites, recents, search | Written + tests |
| Environments | Named environments, globals, collection variables, documented precedence, unresolved-variable warnings, secret variables in secure storage | Written + tests |
| Authentication | None, Basic, Bearer, API key (header/query), OAuth 2.0 Authorization Code + PKCE with refresh | Written + tests |
| History | Recent requests, search, replay, clear, retention by days and count, optional omission of sensitive details, can be turned off | Written + tests |
| Import / export | Import cURL, Postman v2.1, PostBox format, OpenAPI 3 (JSON); export cURL, Postman v2.1, PostBox format; preview, size limits, reports of skipped fields | Written + tests |
| Advanced | Assertions, request chaining (extract values), collection runner with reports, SSE, WebSocket, GraphQL, response diff, command palette | Written (some tests) |
| Settings | Appearance, language and accessibility, requests, editor, data and privacy, keyboard (read-only list), diagnostics, about | Written |

## Not implemented (and why)

- **Pre-request / post-response scripts.** No sandboxed script engine has been evaluated yet; shipping an unsandboxed one would break the security rules. Imported scripts are never executed. Assertions and chaining cover the common cases without scripts.
- **Request comparison** (two requests side by side). Only response diff against the previous response exists.
- **Customizable shortcuts.** Shortcuts are fixed and listed in Settings.
- **AI assistance.** Not present at all, which satisfies "off by default".
- **OpenAPI YAML.** Only JSON documents are parsed.
- **Cookie jar.** Cookies are displayed, never stored or re-sent.
- **Cloud sync, telemetry, crash reporting.** Out of scope for v1.

## Principles

Visual restraint, high information density, privacy by default, no placeholder controls. Every Settings control changes behaviour; where a feature does not exist (crash reporting, sync) Settings says so instead of showing a dead switch.
