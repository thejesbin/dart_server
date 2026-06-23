# Changelog

## 1.0.0

Initial release.

### Routing & requests

- Express-style `DartServer` with `get`/`post`/`put`/`delete`/`patch`/`head`/`options`/`all`.
- Path parameters (`/users/:id`) and a trailing wildcard (`/files/*`); a `*` in
  any non-final segment is rejected at registration.
- Automatic `HEAD` → `GET` fallback with the response body stripped.
- `Request` with `path`, `method`, `headers`, `query`, `params`, `bodyBytes`,
  `body`, `context`, and a lazy, cached `json()`.
- Raw `bodyBytes` always preserved (binary-safe); `body` decodes UTF-8 with
  malformed bytes replaced rather than thrown; `json()` re-throws on every call
  for invalid JSON instead of caching `null`.
- Configurable `maxBodyBytes` (default 1 MiB) — oversized bodies are rejected
  with `413` before any handler runs.
- Malformed percent-encoding in a path segment falls back to the raw value
  instead of producing a `500`.

### Responses

- `Response.json`, `text`, `html`, `status`, `bytes`, `redirect`, fluent `.header()`.
- `HEAD` responses send the `Content-Length` but no body; `204`/`304`/`1xx`
  responses send neither a body nor a `Content-Length`.

### Middleware & errors

- Global middleware with `next()` chaining and per-request `context`.
- Handler errors are converted to responses inside the chain, so middleware
  (and `logger`/`cors`) observe error responses too.
- `HttpError` with status-mapped constructors; customizable `onError`.

### CLI (`dart_server`)

- `dart_server create <name>` — scaffolds a ready-to-run app (entry point, app
  wiring, routes, controllers/models/repositories layout) and runs `pub get`.
- `dart_server dev` — runs with `DART_SERVER_ENV=development` and auto-restarts
  on `.dart` changes under `lib/`/`bin/`; `dart_server prod` runs in production.
- `dart_server make:model|controller|repository|middleware|service|resource` —
  code generators with name normalization (snake/camel/Pascal) and `--force`.
- Installable via `dart pub global activate dart_server`; zero dependencies
  (hand-rolled argument parsing).

### Dev tools

- `app.useDevTools()` — an in-process development dashboard at `/__dev` that
  tracks recent requests (method, path, status, timing, headers, request/
  response bodies), aggregate stats, the live route table and server info, with
  a JSON snapshot at `/__dev/api`. Self-contained (no external assets).
- Development-only: disabled when `DART_SERVER_ENV`/`DART_ENV`/`ENV` is
  production-like; configurable mount path, buffer size and body capture.

### Bundled middleware

- `logger()` — logs successful and errored requests.
- `cors()` — secure by default: `credentials: true` with a wildcard origin is
  refused; use the `origins` allow-list for credentialed cross-origin access.
  Pre-flights are detected by `Access-Control-Request-Method` so explicit
  `app.options(...)` routes still run.
- `serveStatic()` — rejects `..` and symlink path-traversal (real target
  re-checked against the root).

### Other

- Zero external runtime dependencies (built on `dart:io` + `dart:convert`).
- `listen(..., quiet: true)` suppresses the startup banner.
