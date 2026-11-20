# Competitor research

Researched on 2 November 2026 with web searches. Product facts below come from the vendors' own documentation or repositories where possible; where only an aggregator page was found it is marked *(secondary)*. Nothing here says PostBox is better than any of them: PostBox has no benchmarks or user studies. The point is to see which expectations a developer brings from these tools.

## What was checked

| Tool | Licence / model | Local use without an account | Storage | Protocols named in the sources |
|---|---|---|---|---|
| Postman | Commercial platform | Yes, through the "lightweight API Client" when signed out; work stays on the device and can be moved to a workspace after sign-in. The older Scratch Pad is deprecated. | Cloud workspaces; a native Git feature is listed in the docs index | HTTP, WebSocket, Socket.IO, GraphQL, gRPC, MQTT |
| Insomnia | Open source client, accounts and paid tiers | Yes, with the local Scratch Pad | Local Vault, Scratch Pad, Cloud Sync (end-to-end encrypted), Git Sync (documented as Team plan and above) | REST, GraphQL, WebSocket, SSE, gRPC |
| Bruno | MIT, paid commercial editions exist | Yes: offline by design, no account | Plain-text collections (Bru markup) in a folder, shared through Git; the README says cloud sync is not planned | REST and others (secondary: GraphQL, gRPC, WebSocket) |
| Hoppscotch | MIT, enterprise edition for some features (SSO) | Hosted web app or PWA; self-hosting is supported | Cloud or self-hosted backend, offline through the PWA | REST, GraphQL, WebSocket, SSE, Socket.IO, MQTT; desktop app and CLI exist (secondary) |

## What this means for PostBox

1. **Local-first is already a recognised expectation.** Three of four tools offer a no-account mode; Bruno makes it the whole product. PostBox's "no account, no backend, no telemetry" position is normal, not a differentiator.
2. **Git-friendly storage is the gap.** Bruno and Insomnia treat collections as files that can live in Git. PostBox stores collections in SQLite and offers export/import (PostBox JSON, Postman v2.1). A file-based collection format is a candidate for a later release; it is not built.
3. **Protocol coverage.** gRPC and MQTT appear in two of the four tools. PostBox covers HTTP, SSE, WebSocket and GraphQL; gRPC and MQTT are not planned for 0.4.
4. **Storage choices are visible to users.** Insomnia lets people pick local, cloud or Git per project. PostBox's workspaces (0.4) are local only; sync stays out of scope for v1.
5. **Scripts are expected.** Postman and Bruno both run scripts. PostBox uses its own small, sandboxed language instead of JavaScript (see `SCRIPTING.md`); users migrating JavaScript snippets must rewrite them, and imported scripts are never executed.

## Limits of this research

- Short pass: four tools, no hands-on testing, no pricing comparison (plans change often).
- No complaint database. A proper one needs a systematic read of issue trackers and forums, with dates; none was built.
- Star counts, user numbers and "best" claims from aggregator pages were not used.

## Sources

- Postman documentation, lightweight API Client: https://learning.postman.com/docs/getting-started/using-api-client
- Postman documentation, Scratch Pad (deprecated): https://learning.postman.com/docs/getting-started/using-scratch-pad/
- Insomnia storage options (Kong documentation): https://developer.konghq.com/insomnia/storage/
- Insomnia storage options guide: https://docs.insomnia.rest/insomnia/insomnia-storage-options-guide
- Insomnia repository README (forks mirror it): https://github.com/syntax-syndicate/insomnia
- Bruno repository README (forks mirror it): https://github.com/oscarpas/bruno
- Hoppscotch repository README (fork): https://github.com/amk-dev/hoppscotch
- Secondary, treat with care: https://openapps.pro/apps/hoppscotch, https://aiindigo.com/blog/bruno-review-2026-the-git-native-api-client-that-actually-works
