# Roadmap

| Phase | Scope | State |
|---|---|---|
| P0 | Audit, docs, scaffold, CI | Written |
| P1 | Design system, themes, localization (EN/FA, RTL), settings, logo | Written (fonts and icons not bundled) |
| P2 | HTTP engine | Written + tests |
| P3 | Request workspace, inspector, custom editor | Written |
| P4 | Persistence, collections, history, favorites, search | Written + tests (sqlite3, not Drift) |
| P5 | Environments, variables, secrets, redaction | Written + tests |
| P6 | Authentication incl. OAuth 2.0 PKCE | Written + tests |
| P7 | Import / export | Written + tests |
| P8 | Advanced features | Partly: assertions, chaining, runner, SSE, WebSocket, GraphQL, OpenAPI JSON, diff, palette |
| P9 | Release engineering and final audit | Scripts and docs written; nothing built or signed |

## Next

1. First run on a developer machine: `tool/setup_platforms.sh`, format, analyze, test; fix what fails (record results in `PROJECT_STATUS.md`).
2. Bundle fonts, generate icons, take screenshots, fix layout issues.
3. Build and test Android release on a device/emulator, Windows on Windows, Linux on Linux.
4. Sandboxed scripting evaluation, request comparison, shortcut customization.
5. Evaluate SQLCipher and a move back to Drift.
