# Security

PostBox is a local tool that talks to servers you choose. These rules are enforced in code and, where marked, covered by tests.

## Network

- TLS certificate validation is on by default and is never disabled silently. "Allow invalid TLS certificates" is a global setting behind a confirmation dialog, with a permanent warning banner while enabled. *(Setting wiring is covered by builder tests; actual handshake failure behaviour is not yet tested.)*
- Redirects follow an explicit policy (never / same origin / always). `Authorization`, `Cookie` and `Proxy-Authorization` are dropped when a redirect crosses origins. *(Tested against local servers.)*
- Requests are never retried automatically.
- Response size is bounded (default 10 MB, configurable); larger bodies are truncated and marked. Request bodies are bounded as well.
- Proxy: plain `host:port` HTTP proxy. No proxy authentication.
- OAuth endpoints must be https (http is allowed only for localhost for testing).

## Secrets

- Passwords, tokens, API key values, OAuth tokens and "secret" variables are stored through `flutter_secure_storage`, never in the database, preferences, logs or default exports. *(Tested with an in-memory store.)*
- Previews and logs mask secret variable values and sensitive header values. History can omit query values and request bodies (on by default).
- Exports leave secrets out unless the user opts in on the export screen, which shows a warning.
- If the platform keystore is unavailable (for example Linux without libsecret or a keyring service) PostBox keeps secrets in memory for the session and says so in the UI. Install `libsecret-1-0` and a keyring such as GNOME Keyring or KWallet to persist them.

## OAuth 2.0

Authorization Code with PKCE (S256), random `state` validated on return, loopback redirect `http://127.0.0.1:<random port>/callback` on Windows and Linux, custom scheme `com.uniqueone.postbox:/oauth2redirect` on Android (needs the manifest intent filter added by `tool/setup_platforms.sh`). Refresh tokens are used when present. Not supported: implicit, password, client-credentials and device flows.

## Untrusted input

- Imports are size limited (10 MB), validated, previewed and never execute scripts.
- Remote HTML is never rendered; it is shown as text.
- Cookie values are hidden until revealed.
- Filenames for saved responses and exports are generated, not taken from the server.

## Not done / limits

- No encryption of the SQLite file (SQLCipher was to be evaluated later). Collections, URLs and history are stored in plain text on disk; rely on OS disk encryption.
- No code signing or update mechanism is included.

## Reporting vulnerabilities

Please report privately to the maintainers (a contact address must be set in the repository's `SECURITY.md` when it is published). Do not open public issues for vulnerabilities.
