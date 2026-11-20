# PostBox Script

Pre-request and post-response scripts use **PostBox Script**, a small language interpreted by the app itself. It is deliberately not JavaScript: there is no embedded JavaScript engine, no `eval`, no way to load code, and no access to files, sockets, the clipboard, the operating system or the app's secrets.

Scripts can be attached to a request (Scripts tab), a folder or a collection (right-click > Auth, headers and scripts).

## When scripts run

1. Collection pre-script, folder pre-scripts (outermost first), then the request's pre-script.
2. The request is sent.
3. Extractions and assertions of the request are evaluated.
4. The request's post-script, then folder post-scripts (innermost first), then the collection post-script.

A failing pre-script stops the request: nothing is sent and the error (with line number) is shown. A failing post-script keeps the response and reports the error in the Tests tab.

## Language

```
// comment
let name = "value";            // variables (block scoped)
name = name + "!";             // assignment (variable must exist)
if (x > 1) { ... } else if (x == 1) { ... } else { ... }
for item in [1, 2, 3] { ... }   // lists, or the keys of an object
```

- Values: numbers, strings (`"..."` or `'...'`), `true`, `false`, `null`, lists `[1, 2]`, objects `{"a": 1}`.
- Operators: `+ - * / %`, `== !=`, `< <= > >=`, `&& || !`, `??` (first non-null).
- Indexing and members: `list[0]`, `obj.key`, `obj["key"]`, `text.length`, `list.length`.
- Strings: `contains startsWith endsWith toUpperCase toLowerCase trim split replace substring`.
- Lists: `contains join push`. Objects: `has keys`.
- `==` compares numbers, strings, lists and objects by value. `0`, `""`, `null` and `false` are false in conditions.
- Semicolons are optional. There are no functions, classes, `while` loops or imports.

## Objects and functions

| Name | Where | What it does |
|---|---|---|
| `vars.get(name)`, `vars.has(name)` | both | Reads a variable. **Secret variables read as `null`.** |
| `vars.set(name, value)` | both | Sets a (non-secret) variable. Stored like an extraction: in the active environment, or in the globals when none is active; the runner keeps it in memory per iteration. A script can overwrite a secret variable but never read it. |
| `request.method`, `request.url`, `request.body` | pre: read/write, post: read | `body` is writable for JSON, text, raw and GraphQL bodies only. |
| `request.headers.get/set/remove/has(name)` or `request.headers["Name"]` | pre: read/write, post: read | Case-insensitive. |
| `response.status`, `response.reason`, `response.time` (ms), `response.size`, `response.url`, `response.body` | post | Response facts. |
| `response.json()`, `response.text()`, `response.header(name)`, `response.headers.get(name)` | post | `json()` is a script error if the body is not JSON. |
| `test(name, condition)` | both | Adds a test result (shown in Tests; counts in the runner). |
| `log(...)` | both | Adds a line to the script log (200 lines, 2000 characters each). |
| `fail(message)` | both | Stops the script with an error. |
| `now()`, `uuid()` | both | Milliseconds since the epoch; a random id. |
| `str`, `num`, `len`, `json`, `parseJson` | both | Conversions. |
| `base64`, `base64decode`, `urlencode`, `sha256`, `hmacSha256(key, message)` | both | Helpers for signing and encoding (hex output for hashes). |

## Limits

| Limit | Value |
|---|---|
| Script length | 100,000 characters |
| Nesting of blocks / expressions | 40 / 160 |
| Evaluation steps per script | 50,000 |
| Run time per script | 2 seconds (checked every 256 steps) |
| String length | 1,000,000 characters |
| List length | 10,000 items |
| Variables set per run | 200, values up to 100,000 characters |

Because there is no `while` and loops only run over existing lists, a script cannot loop forever; the step and time limits are a second line of defence.

## Security notes

- Scripts see no secrets: secret variables read as `null`, auth tokens are not exposed, and `response`/`request` only expose what is listed above.
- Scripts have no file, network or process access.
- **Scripts that arrive in a file are never imported or run.** PostBox-format and Postman imports drop script blocks and say so in the preview. Add scripts yourself after reviewing them.
- Scripts you wrote do run automatically when you send. A script can change the URL and headers of the request (including adding a header from a variable), so review scripts in collections you did not write.

## Examples

Add a timestamp header and a signature:

```
let ts = str(now());
request.headers.set("X-Timestamp", ts);
request.headers.set("X-Signature", hmacSha256(vars.get("hmac_key") ?? "", ts + request.url));
```

(`hmac_key` must be a non-secret variable to be readable. Secret variables are invisible to scripts by design.)

Check a response and pass a value on:

```
let data = response.json();
test("status is 200", response.status == 200);
test("has an id", data.id != null);
vars.set("order_id", str(data.id));
```

## Known differences from JavaScript

No functions or closures, no `while`, no `===`, no regular expressions, no dates beyond `now()`, strings compare with `<` only against strings, and `+` between a number and a string concatenates. Postman `pm.*` scripts do not work and are not converted.
