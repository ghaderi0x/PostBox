# Security

- TLS validation is on by default. `allowInvalidCertificates` is an explicit per-request opt-in and must be visibly flagged in the UI.
- Sensitive headers are never forwarded across origins on redirect (tested).
- Response size is bounded; large bodies are truncated and marked.
- Secrets go to secure storage only; never to preferences, plaintext DB, logs or default exports.
- Imported scripts are never executed.
- No telemetry. Report vulnerabilities privately to the maintainers (contact to be added to the repository SECURITY policy).
