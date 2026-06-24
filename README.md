# dart_server

A lightweight, **Express.js-like** HTTP server framework for Dart with an
optional **NestJS-style** modular layer. Build REST APIs with familiar routing,
middleware and JSON helpers — using only the Dart SDK. **Zero external runtime
dependencies.**

```dart
import 'package:dart_server/dart_server.dart';

void main() async {
  final app = DartServer();

  app.use(logger());

  app.get('/', (req) => Response.text('Hello World'));

  app.get('/users/:id', (req) {
    return Response.json({'id': req.params['id']});
  });

  app.post('/login', (req) async {
    final body = await req.json();
    return Response.json({'token': 'abc'});
  });

  await app.listen(3000);
}
```

---

## Features

- **Express-style routing** — `get` / `post` / `put` / `delete` / `patch` / `head` / `options` / `all`
- **Path params & wildcards** — `/users/:id`, `/files/*`
- **Middleware** — composable `(req, next)` chain with per-request `context`
- **JSON in/out** — `await req.json()` and `Response.json(...)` with correct headers
- **Query parsing** — `req.query['q']`
- **Global error handling** — throw `HttpError.notFound('...')`, get JSON back
- **Bundled middleware** — `logger()`, `cors()`, `serveStatic()`
- **Modular architecture** — NestJS-style modules, controllers & dependency injection (optional)
- **Dev dashboard** — built-in request tracker at `/__dev` (dev only)
- **CLI** — scaffold projects, run dev/prod, generate modules/controllers/services
- **No dependencies** — built on `dart:io` + `dart:convert`, null-safe

## Contents

- [Installation](#installation)
- [Usage](#usage) — routing, request, response, middleware, errors
- [Bundled middleware](#bundled-middleware) — logging, CORS, static files
- [Modular architecture](#modular-architecture) — modules, controllers, DI
- [CLI](#cli) — scaffold, run, generate
- [Dev tools](#dev-tools) — the development dashboard
- [Project structure](#project-structure)

---

## Installation

```sh
dart pub add dart_server
```

Or add it to your `pubspec.yaml`:

```yaml
dependencies:
  dart_server: ^1.0.0
```

Requires Dart SDK `^3.0.0`.

---

## Usage

### Server setup

```dart
final app = DartServer();                     // 1 MiB default body limit
final app = DartServer(maxBodyBytes: 5 << 20);// raise the limit to 5 MiB
await app.listen(3000);                       // all interfaces, port 3000
await app.listen(8080, address: '127.0.0.1'); // localhost only
await app.listen(3000, quiet: true);          // suppress the startup banner
await app.listen(0);                          // ephemeral port (great for tests)
await app.close();                            // stop serving
```

Request bodies are capped at `maxBodyBytes` (default 1 MiB); a larger body is
rejected with `413 Payload Too Large` before any handler runs. Pass `0` to
disable the limit.

### Routing

```dart
app.get('/users', listUsers);
app.post('/users', createUser);
app.put('/users/:id', updateUser);
app.delete('/users/:id', deleteUser);
```

Routes are matched in registration order. A path that exists but doesn't match
the request method returns `405 Method Not Allowed` with an `Allow` header;
anything unmatched returns `404`. A `HEAD` request with no explicit `HEAD` route
is served by the matching `GET` handler with the body stripped.

### Route parameters

```dart
app.get('/users/:id/posts/:postId', (req) {
  return Response.json({
    'user': req.params['id'],
    'post': req.params['postId'],
  });
});
```

A trailing `*` captures the rest of the path under `req.params['*']`:

```dart
app.get('/files/*', (req) => Response.text('path: ${req.params['*']}'));
```

### The Request object

| Member             | Description                                                       |
| ------------------ | ----------------------------------------------------------------- |
| `req.method`       | HTTP method, upper-cased (`GET`, `POST`, …)                       |
| `req.path`         | Path without the query string                                     |
| `req.headers`      | Lower-cased header map                                            |
| `req.query`        | Parsed query string (`?q=dart` → `{'q': 'dart'}`)                 |
| `req.params`       | Route parameters (`/users/:id` → `{'id': '42'}`)                  |
| `req.bodyBytes`    | Raw body bytes, always preserved (binary / uploads)               |
| `req.body`         | Body decoded as UTF-8 (invalid bytes → U+FFFD, never throws)      |
| `await req.json()` | Parsed, cached JSON body; `null` if empty; throws if invalid JSON |
| `req.contentType`  | Value of the `Content-Type` header, or `null` if absent           |
| `req.isJson`       | `true` when `Content-Type` contains `application/json`            |
| `req.context`      | Per-request scratch space shared across middleware                |
| `req.raw`          | The underlying `HttpRequest` for advanced needs                   |

```dart
app.post('/login', (req) async {
  final data = await req.json() as Map<String, dynamic>;
  final email = data['email'];
  ...
});
```

### The Response object

```dart
Response.json({'ok': true});           // 200, application/json
Response.text('Hello');                // 200, text/plain
Response.html('<h1>Hi</h1>');          // 200, text/html
Response.status(201, {'id': 1});       // explicit status + JSON
Response.status(204);                  // empty body
Response.bytes(bytes, contentType: ct);// raw bytes
Response.redirect('/login');           // 302 redirect

// Headers can be chained:
Response.json(data).header('X-Total-Count', '42');
```

### Middleware

Middleware receives the request and a `next` continuation. Call `next()` to
run the rest of the chain; return early to short-circuit it.

```dart
// Logging
app.use((req, next) async {
  print('${req.method} ${req.path}');
  return await next();
});

// Auth guard that short-circuits
app.use((req, next) async {
  if (req.headers['authorization'] == null) {
    return Response.status(401, {'error': 'Unauthorized'});
  }
  req.context['user'] = decodeToken(req.headers['authorization']!);
  return await next();
});
```

### Error handling

Throw anywhere in a handler or middleware and it becomes a JSON response.
`HttpError` carries a status code:

```dart
app.get('/users/:id', (req) async {
  final user = await db.find(req.params['id']);
  if (user == null) throw HttpError.notFound('No such user');
  return Response.json(user);
});
// -> 404 {"error": "No such user", "statusCode": 404}
```

Anything else maps to `500`. Customize the mapping with `onError`:

```dart
app.onError((req, error, stackTrace) {
  if (error is HttpError) {
    return Response.json(error.toJson(), status: error.statusCode);
  }
  return Response.json({'error': 'Something broke'}, status: 500);
});
```

`HttpError` ships with handy constructors: `badRequest`, `unauthorized`,
`forbidden`, `notFound`, `conflict`, `unprocessable`, `internal`.

> **Security note:** an `HttpError`'s `message` and `details` are serialized
> into the client-visible response body. Don't pass raw exception output
> (`throw HttpError.badRequest(e.toString())`) — it can leak internal paths or
> query fragments. The built-in `500` handler never echoes the exception; it
> logs the stack trace to stderr and returns a generic body.

Because handler errors are converted to a response *inside* the chain, your
middleware (including `logger` and `cors`) observes error responses just like
successful ones.

---

## Bundled middleware

### Logging

```dart
app.use(logger());                          // "GET /users/42 200 1ms"
app.use(logger(includeTimestamp: true));    // prefixed with an ISO-8601 stamp
```

### CORS

```dart
app.use(cors());                            // wide open (dev only)
app.use(cors(origin: 'https://app.example.com'));   // single fixed origin
app.use(cors(                                       // credentialed allow-list
  origins: ['https://app.example.com', 'https://admin.example.com'],
  credentials: true,
  allowedHeaders: ['Content-Type', 'Authorization'],
));
```

`cors()` also accepts `methods`, `exposedHeaders` and `maxAge`. Browser
pre-flights (an `OPTIONS` with `Access-Control-Request-Method`) are answered
automatically with `204`; other `OPTIONS` requests fall through to any route you
registered with `app.options(...)`.

> **Security note:** combining `credentials: true` with the default wildcard
> origin (`*`) is refused with an `ArgumentError`, because reflecting an
> arbitrary `Origin` alongside `Access-Control-Allow-Credentials: true` lets any
> site read authenticated responses. Use the `origins` allow-list for
> credentialed cross-origin access — the request's `Origin` is echoed only when
> it is a member.

### Static files

```dart
app.use(serveStatic('public'));                  // serve ./public at /
app.use(serveStatic('build', urlPrefix: '/app'));// mount under /app
```

Requests that don't map to a file fall through to your routes. Directory
requests serve `index.html`. Path-traversal attempts — both `..` and symlinks
whose real target escapes the root — are rejected with `403`.

---

## Modular architecture

For larger apps, dart_server offers an optional **NestJS-style** layer:
**modules** that group **controllers** and **providers** (services), wired
together with **dependency injection**. It's plain Dart — no decorators,
reflection or code generation — so wiring is explicit and analyzable.

```dart
import 'package:dart_server/dart_server.dart';

// A provider (service) — just a class.
class UsersService {
  final _users = [{'id': '1', 'name': 'Ada'}];
  List<Map<String, String>> all() => _users;
}

// A controller — groups routes under a base path, deps via the constructor.
class UsersController extends Controller {
  UsersController(this._users);
  final UsersService _users;

  @override
  String get basePath => '/users';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.json(_users.all()));
  }
}

// A module wires providers + controllers and exports what others may inject.
Module usersModule() => Module(
      providers: [Provider.singleton((i) => UsersService())],
      controllers: [(i) => UsersController(i.get<UsersService>())],
      exports: [UsersService],
    );

Module appModule() => Module(imports: [usersModule()]);

Future<void> main() async {
  final app = await DartServerFactory.create(appModule());
  app.use(logger());
  await app.listen(3000);
}
```

**Providers / DI.** `Provider.singleton((i) => …)` (one shared instance),
`Provider.transient((i) => …)` (new each time) and `Provider.value(instance)`.
Resolve dependencies with `i.get<T>()`. The container instantiates everything
up front, so missing providers and circular dependencies fail fast with a
`DiError`.

**Encapsulation.** A module can only inject providers it declares itself or that
an imported module `exports`. Mark a module `isGlobal: true` to expose its
exports everywhere.

**Lifecycle.** A provider or controller implementing `OnInit` has its
`onInit()` awaited during bootstrap (in dependency order) — handy for opening
connections.

**Controllers.** Extend `Controller`, set `basePath`, and declare routes in
`register(RouteRegistrar)`. The factory mounts each route at `basePath + path`.

The manual `DartServer()` API and the modular layer are fully interoperable —
`DartServerFactory.create` returns an ordinary `DartServer`, so you can still
add middleware, `useDevTools()`, or extra routes on it. The [CLI](#cli)
scaffolds and generates this structure for you.

---

## CLI

`dart_server` ships a command-line tool that scaffolds modular projects, runs
them in dev/prod, and generates modules, controllers, services and more.

Install it on your `PATH`:

```sh
dart pub global activate dart_server
# or, from a checkout:  dart pub global activate --source path .
```

(You can also run it without installing, from inside a project that depends on
dart_server: `dart run dart_server:dart_server <command>`.)

### Create a project

```sh
dart_server create blog          # scaffolds ./blog and runs `dart pub get`
cd blog
```

You get a ready-to-run modular app:

```text
bin/server.dart          entry point — bootstraps appModule() via DartServerFactory,
                         wires dev dashboard + logger + cors, reads DART_SERVER_PORT (default 3000)
lib/app_module.dart      the root Module (appModule()) — import feature modules here
lib/app_controller.dart  AppController — serves GET / and GET /health
lib/modules/             feature modules (added by make:resource / make:module)
pubspec.yaml  analysis_options.yaml  .gitignore  README.md
```

`create` (alias `new`) accepts `--local <path>` to depend on a local
dart_server checkout (path dependency) instead of the published `^1.0.0`,
`--force` to scaffold into a non-empty directory, and `--no-pub-get` to skip the
automatic `dart pub get`.

### Run

```sh
dart_server dev  [--port <n>] [--entry <file>] [--no-watch]   # development
dart_server prod [--port <n>] [--entry <file>]                # production
dart_server run  [--prod] [--port <n>] [--entry <file>]       # dev by default
```

- `dev` (and `run` without `--prod`) sets `DART_SERVER_ENV=development` and
  restarts the server whenever a `.dart` file under `lib/` or `bin/` changes.
  `--no-watch` disables auto-restart.
- `prod` (and `run --prod`) sets it to `production`; production never watches.
- `--entry <file>` overrides the entry point (default `bin/server.dart`);
  `--port <n>` sets `DART_SERVER_PORT`.

### Generate code

Feature files are generated under `lib/modules/<name>/`:

```sh
dart_server make:resource Post    # model + repository + service + controller + module
dart_server make:module Order     # lib/modules/order/order_module.dart
dart_server make:controller User  # lib/modules/user/user_controller.dart  (REST handlers)
dart_server make:service Billing  # lib/modules/billing/billing_service.dart
dart_server make:repository User  # lib/modules/user/user_repository.dart
dart_server make:model User       # lib/modules/user/user.dart             -> class User

# Cross-cutting middleware lives outside the feature folders:
dart_server make:middleware Auth  # lib/middleware/auth_middleware.dart
```

`make:resource` generates five wired files (model → repository → service →
controller → module). After `make:module` / `make:resource` the CLI prints a
reminder to register the new module in `lib/app_module.dart`.

Names are normalized, so `make:controller user_account`,
`make:controller UserAccount` and `make:controller UserAccountController` all
produce class `UserAccountController` in
`lib/modules/user_account/user_account_controller.dart`. Add `--force` to
overwrite an existing file.

---

## Dev tools

A built-in development dashboard that tracks your API as you build it — recent
requests (method, path, status, timing, headers, request/response bodies),
aggregate stats, the live route table and server info.

```dart
final app = DartServer();
app.useDevTools();              // mounts the dashboard at /__dev
// ... routes ...
await app.listen(3000);
```

Open **`http://localhost:3000/__dev`** — it auto-refreshes, lets you click any
request to inspect it, and has a Clear button. It's served entirely in-process
with no external assets.

```dart
app.useDevTools(
  path: '/_inspect',     // custom mount path (default /__dev)
  maxRequests: 250,      // ring-buffer size (default 100)
  captureBodies: false,  // don't record request/response bodies
);
```

You can also read the recorded data programmatically via `app.devTools` (e.g.
`app.devTools?.snapshot()`), or fetch the JSON snapshot at `/__dev/api`.

> **Development only.** The dashboard exposes request headers and bodies, so it
> never mounts when `DART_SERVER_ENV` / `DART_ENV` / `ENV` holds a
> production-like value — `production`, `prod`, `staging`, or `release`
> (case-insensitive). Set one of those in production — or pass `enabled: false`.
> When the variable is unset the environment is treated as development (the Node
> `NODE_ENV` convention), so it works out of the box under `dart run`. Force it
> with `app.useDevTools(enabled: true)`.

---

## Project structure

This is how an app you build with dart_server is laid out — exactly what
`dart_server create` plus the `make:*` generators produce (and what the
runnable [`example/`](example) in this repo mirrors):

```text
your_app/
├── bin/
│   └── server.dart                 # entry point — bootstraps appModule()
├── lib/
│   ├── app_module.dart             # root module — imports feature modules
│   ├── app_controller.dart         # root controller (serves / and /health)
│   ├── modules/                    # one self-contained folder per feature
│   │   └── users/                  # e.g. `dart_server make:resource Users`
│   │       ├── users.dart              # model
│   │       ├── users_repository.dart   # data access
│   │       ├── users_service.dart      # business logic (provider)
│   │       ├── users_controller.dart   # routes under /users
│   │       └── users_module.dart       # wires the feature together
│   └── middleware/                 # cross-cutting middleware (make:middleware)
├── pubspec.yaml
└── analysis_options.yaml
```

Each feature is fully encapsulated in its own `lib/modules/<feature>/` folder
(model, repository, service, controller, module), then imported into
`app_module.dart`.

---

## Running the example & tests

The package ships a runnable example built in this exact layout:

```sh
dart run example/main.dart   # starts the demo on :3000 (try /, /users, /users/1)
```

To work on dart_server itself:

```sh
dart test                    # run the test suite
dart analyze                 # static analysis
```

---

## License

[MIT](LICENSE)
