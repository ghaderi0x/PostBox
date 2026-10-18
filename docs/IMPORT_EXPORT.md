# Import and export

All imports are limited to 10 MB, validated, shown in a preview with notes, and committed in one database transaction. Nothing from an import is executed.

## Import

| Format | Notes |
|---|---|
| cURL | Method, URL (query split into params), headers, `-d/--data*`, `--data-urlencode`, `-F`, `-u`, `-G`, `-I`, `-A`, `-b`. A `Bearer` header becomes Bearer auth. `-k` is reported and **not** honoured. Unsupported options are reported. Windows `cmd` carets are not supported. Opens as a new request tab. |
| Postman Collection v2.1 | Folders, requests, query, headers, bodies (raw, urlencoded, formdata, graphql), auth (bearer, basic, apikey), collection variables. v2.0 accepted with a warning. **Scripts and test events are skipped and counted.** OAuth 2.0 and other auth types are imported without auth and reported. Variables whose names look like secrets are flagged. |
| PostBox | Versioned JSON (`"format": "postbox"`, `"version": 1`). Requests get fresh ids; environments are imported too. Newer versions are refused. |
| OpenAPI 3 (JSON) | Servers become `base_url`; tags become folders; path/query/header parameters; JSON request body examples generated from `example` or schema. Security schemes are reported, not applied. **YAML is not supported.** |

## Export

| Format | Notes |
|---|---|
| cURL | Current request. Variables stay as `{{name}}`. Secrets become placeholders (`<token>`, `<password>`). |
| Postman v2.1 | One collection. **Lossy:** assertions, chaining and OAuth 2.0 settings have no equivalent and are dropped. Secrets blank by default. |
| PostBox | One collection plus optionally all environments. Lossless for everything PostBox stores. |

**Secrets** (passwords, tokens, API key values, secret variable values) are left out unless the user switches on "Include secrets", which shows a warning.

## Where files go

There is no file picker dependency. Import reads a path you type (or pasted text). "Save" writes to `Documents/PostBox/exports` or `Documents/PostBox/responses` and shows the path.
