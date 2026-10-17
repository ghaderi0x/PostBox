# PostBox Product Spec

PostBox is an open-source, local-first HTTP API client by Uniqueone. No account, backend or internet is needed for local workflows.

**Platforms:** Android, Windows, Linux. **Languages:** English (LTR), Persian (RTL). **Licence:** MIT.

## Feature set and status

| Area | Scope | Status |
|---|---|---|
| HTTP engine | methods, timeout, cancel, redirects, size limit, proxy, TLS | Partly implemented (P2 core, unverified, see PROJECT_STATUS) |
| Design system | semantic tokens, 6 themes | Orange light/dark tokens only |
| Request workspace | URL, params, headers, body, send/cancel | Planned (P3) |
| Response inspector | preview, raw, JSON, headers, search | Planned (P3) |
| Custom editor | highlighting, folding, find, RTL-aware | Planned (P3) |
| Collections, history | Drift, nested folders, favorites, search | Planned (P4) |
| Environments, secrets | precedence, redaction | Planned (P5) |
| Auth | Basic, Bearer, API key, OAuth2 PKCE | Planned (P6) |
| Import/export | cURL, Postman v2.1, PostBox format | Planned (P7) |
| Advanced | scripts, runner, WebSocket, SSE, GraphQL, OpenAPI | Planned (P8) |

## Non-goals (v1)
Cloud sync, telemetry, iOS/macOS/web, any AI dependency in the core client.

## Principles
Visual restraint, high information density, privacy by default, no dead controls.
