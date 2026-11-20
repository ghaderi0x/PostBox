# Test fixtures

`localhost_cert.pem` and `localhost_key.pem` are a throw-away self-signed certificate (CN=localhost, SAN localhost and 127.0.0.1, valid for 100 years) used only by the TLS, mutual-TLS and HTTP/2 tests. The private key protects nothing: it was generated for these tests, is not used anywhere else and must never be reused. Secret scanners may flag the key file; it is intentionally committed.

Regenerate with:

```
openssl req -x509 -newkey rsa:2048 -nodes -keyout localhost_key.pem -out localhost_cert.pem \
  -days 36500 -subj "/CN=localhost/O=PostBox test fixture" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```
