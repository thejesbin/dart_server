# dart_server

A **NestJS-style backend framework for Dart** — modules, dependency injection,
guards, interceptors and exception filters on top of a fast Express-like core.
Scaffold a full project with one command. Built only on `dart:io` +
`dart:convert`: **zero external dependencies**, no reflection, no code
generation.

## Quick start

```sh
dart pub global activate dart_server   # install the CLI
dart_server create my_app              # scaffold a project (+ dart pub get)
cd my_app
dart_server dev                        # run: auto-restart + dashboard at /__dev
```

That's it — you have a running, tested, modular API:

```text
my_app/
├── bin/server.dart          entry point — bootstraps the root module
├── lib/
│   ├── app_module.dart      root module (providers + controllers)
│   ├── app_controller.dart  routes: GET /  and  GET /health
│   ├── app_service.dart     business logic, injected into the controller
│   └── modules/             feature modules live here
├── test/
│   ├── app_test.dart          end-to-end test over real HTTP
│   └── app_service_test.dart  unit test with a fake Env
├── .env.example             configuration template (copy to .env)
└── pubspec.yaml
```

Grow it one feature at a time:

```sh
dart_server make:resource Post   # model + repository + service + controller + module
dart_server make:guard Auth      # a CanActivate-style guard
dart test                        # the scaffold ships with passing tests
dart_server prod                 # production mode (dashboard off, no watch)
```

## Contents

- [Architecture](#architecture) — modules, DI, controllers, the request pipeline
- [Guards](#guards) · [Interceptors](#interceptors) · [Exception filters](#exception-filters)
- [Lifecycle](#lifecycle) · [Configuration](#configuration-env)
- [CLI reference](#cli-reference)
- [The Express-style core](#the-express-style-core)
- [Bundled middleware](#bundled-middleware) · [Dev tools](#dev-tools)
- [Using it as a library](#using-it-as-a-library)

---

## Architecture

dart_server follows NestJS's mental model — **modules** group **controllers**
and **providers**, wired by **dependency injection** — expressed as plain,
analyzable Dart instead of decorators:

```dart
import 'package:dart_server/dart_server.dart';

// A provider (service): just a class.
class UsersService {
  List<Map<String, Object>> all() => [{'id': 1, 'name': 'Ada'}];
}

// A controller: routes under a base path, dependencies via the constructor.
class UsersController extends Controller {
  UsersController(this._users);
  final UsersService _users;

  @override
  String get basePath => '/users';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.json(_users.all()));
    routes.get('/:id', (req) => Response.json({'id': req.paramInt('id')}));
  }
}

// A module: providers + controllers + what it exports to importers.
Module usersModule() => Module(
      providers: [Provider.singleton((i) => UsersService())],
      controllers: [(i) => UsersController(i.get<UsersService>())],
      exports: [UsersService],
    );

Module appModule() => Module(imports: [usersModule()]);

Future<void> main() async {
  final app = await DartServerFactory.create(appModule());
  app.use(logger());
  app.enableShutdownHooks();
  await app.listen(3000);
}
```

**Providers & DI.** `Provider.singleton((i) => …)` (one shared instance),
`Provider.transient((i) => …)` (new per resolution), `Provider.value(instance)`.
Resolve with `i.get<T>()`. All singleton/value providers and every controller
are instantiated at bootstrap, so missing providers and circular dependencies
in that graph fail fast with a `DiError`; transients are created per
resolution.

**Encapsulation.** A module can only inject providers it declares or that an
imported module `exports`. `isGlobal: true` makes a module's exports visible
everywhere.

**The request pipeline.** Every controller route runs through the Nest
lifecycle:

```text
global middleware (app.use)
  -> controller middleware -> route middleware
    -> guards        (global -> controller -> route)
      -> interceptors (global -> controller -> route)
        -> handler
  errors from guards/interceptors/handler
    -> exception filters (route -> controller -> global)
      -> built-in mapping (onError, HttpError, 500)
```

### Guards

The `CanActivate` equivalent: decide whether a request proceeds. `false`
rejects with `403`; throw an `HttpError` for anything else.

```dart
class ApiKeyGuard implements Guard {
  @override
  bool canActivate(Request req) => req.headers['x-api-key'] == 'secret';
}
```

Attach at any of three levels:

```dart
// Globally — every controller route:
final app = await DartServerFactory.create(appModule(), guards: [ApiKeyGuard()]);

// Per controller:
class AdminController extends Controller {
  @override
  List<Guard> get guards => [ApiKeyGuard()];
  ...
}

// Per route (and inline, with Guard.from):
routes.post('/', create, guards: [Guard.from((req) => req.context['user'] != null)]);
```

Use `req.context` to hand what a guard learns (the authenticated user, tenant,
roles) to interceptors and handlers. Note that the request body is buffered
(capped by `maxBodyBytes`) before routing, so guards gate your logic — the
body-size limit is what protects against oversized uploads.

### Interceptors

Wrap handler execution **after guards pass** — timing, caching, response
shaping. Same `(req, next)` shape as middleware:

```dart
Middleware timing() => (req, next) async {
      final sw = Stopwatch()..start();
      final res = await next();
      return res.header('x-response-time', '${sw.elapsedMilliseconds}ms');
    };

// Attach globally (create(interceptors: [...])), per controller
// (get interceptors), or per route (interceptors: [...]).
```

Controller/route **middleware** uses the same shape but runs *before* guards —
use middleware for cross-cutting plumbing, interceptors for logic that must
only run for authorized requests.

### Exception filters

Convert errors into responses, most-specific-first. A filter picks the errors
it owns with an `is` check and returns `null` for the rest:

```dart
class TimeoutFilter implements ExceptionFilter {
  @override
  Response? handle(Request req, Object error, StackTrace stackTrace) {
    if (error is TimeoutException) {
      return Response.json({'error': 'Upstream timed out'}, status: 504);
    }
    return null; // not ours — next filter / built-in mapping
  }
}
```

Attach per route (`filters: [...]`), per controller (`get filters`) or globally
(`create(filters: [...])`). Anything unhandled falls through to the built-in
mapping: a thrown `HttpError` becomes its status code, everything else a `500`
(customizable with `app.onError`).

### Lifecycle

```dart
class Database implements OnInit, OnShutdown {
  @override
  Future<void> onInit() async => _pool = await connect();   // at bootstrap

  @override
  Future<void> onShutdown() async => _pool.close();         // at close
}
```

`OnInit` runs during `DartServerFactory.create`, in dependency order.
`OnShutdown` runs when the app closes, in **reverse** creation order
(dependents first). To run shutdown hooks on Ctrl-C / SIGTERM (containers!),
call:

```dart
app.enableShutdownHooks();
```

### Configuration (Env)

Zero-dep `.env` + environment configuration — the `@nestjs/config` role:

```dart
final env = Env.load();                 // .env file + Platform.environment
env['APP_NAME'];                        // String? (env vars win over .env)
env.getInt('PORT') ?? 3000;             // typed access
env.getBool('FEATURE_X') ?? false;      // true/1/yes/on · false/0/no/off
env.require('DATABASE_URL');            // throws if missing
```

The scaffold registers it as a provider (`Provider.singleton((i) => Env.load())`)
so any service can inject it — and `Env.fromMap({...})` makes services trivial
to unit-test.

---

## CLI reference

```sh
dart pub global activate dart_server
# or run in-project without installing: dart run dart_server:dart_server <cmd>
```

### Project

```sh
dart_server create <name>    # scaffold a new app, then `dart pub get`
                             #   --local <path>   use a local dart_server checkout
                             #   --force          write into a non-empty directory
                             #   --no-pub-get     skip dependency install

dart_server dev              # DART_SERVER_ENV=development + auto-restart on change
dart_server prod             # DART_SERVER_ENV=production (no watch, no dashboard)
dart_server run [--prod]     # dev by default
# all run commands accept:  --port <n>  --entry <file>   (dev also: --no-watch)
```

### Generators

Feature files land in `lib/modules/<name>/`; names are normalized
(`user_account`, `UserAccount` and `UserAccountController` are equivalent).
Add `--force` to overwrite.

```sh
dart_server make:resource Post    # model + repository + service + controller + module
dart_server make:module Order     # lib/modules/order/order_module.dart
dart_server make:controller User  # lib/modules/user/user_controller.dart
dart_server make:service Billing  # lib/modules/billing/billing_service.dart
dart_server make:repository User  # lib/modules/user/user_repository.dart
dart_server make:model User       # lib/modules/user/user.dart

dart_server make:guard Auth       # lib/guards/auth_guard.dart
dart_server make:interceptor Log  # lib/interceptors/log_interceptor.dart
dart_server make:filter Domain    # lib/filters/domain_filter.dart
dart_server make:middleware Cors  # lib/middleware/cors_middleware.dart
```

After `make:module` / `make:resource`, the CLI prints the import line to add
to `lib/app_module.dart`.

---

## The Express-style core

The modular layer is optional — `DartServerFactory.create` returns an ordinary
`DartServer`, and you can also use it directly, Express-style:

```dart
final app = DartServer();                      // maxBodyBytes: 1 MiB default
app.get('/', (req) => Response.text('Hello'));
app.get('/users/:id', (req) => Response.json({'id': req.params['id']}));
app.post('/login', (req) async => Response.json(await req.json()));
await app.listen(3000);                        // quiet: true to silence banner
```

Routing is registration-order; unmatched paths → `404`, wrong method → `405`
with an `Allow` header, `HEAD` falls back to `GET` with the body stripped.
Path params (`/users/:id`) and trailing wildcards (`/files/*` →
`req.params['*']`) are supported. Bodies over `maxBodyBytes` are rejected with
`413` before your code runs.

### Request

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
| `req.context`      | Per-request scratch space shared across the pipeline              |
| `req.raw`          | The underlying `HttpRequest` for advanced needs                   |

**Typed helpers** (the ParseIntPipe equivalents — bad input becomes a `400`,
not a `500`):

```dart
final id = req.paramInt('id');            // /users/abc -> 400 Bad Request
final page = req.queryInt('page') ?? 1;   // ?page=two  -> 400
final exact = req.queryBool('exact');     // true/1/yes/on · false/0/no/off
final body = await req.jsonMap();         // non-object or invalid JSON -> 400
```

### Response

```dart
Response.json({'ok': true});            // 200, application/json
Response.text('Hello');                 // 200, text/plain
Response.html('<h1>Hi</h1>');           // 200, text/html
Response.status(201, {'id': 1});        // explicit status + JSON
Response.status(204);                   // empty body
Response.bytes(bytes, contentType: ct); // raw bytes
Response.redirect('/login');            // 302
Response.json(data).header('X-Total-Count', '42');  // chainable headers
```

### Middleware & errors

```dart
app.use((req, next) async {
  if (req.headers['authorization'] == null) {
    return Response.status(401, {'error': 'Unauthorized'}); // short-circuit
  }
  return next();
});

app.get('/users/:id', (req) async {
  final user = await db.find(req.paramInt('id'));
  if (user == null) throw HttpError.notFound('No such user');
  return Response.json(user);
});
// -> 404 {"error": "No such user", "statusCode": 404}
```

`HttpError` constructors: `badRequest`, `unauthorized`, `forbidden`,
`notFound`, `conflict`, `unprocessable`, `tooManyRequests`, `internal`,
`serviceUnavailable`. Customize the fallback mapping with
`app.onError((req, error, stackTrace) => ...)`.

> **Security note:** `HttpError.message`/`details` are serialized into the
> client-visible body — never pass raw exception output. The built-in `500`
> handler logs the stack trace to stderr and returns a generic body.

Handler errors are converted to responses *inside* the chain, so global
middleware (including `logger` and `cors`) observe error responses like any
other.

---

## Bundled middleware

```dart
app.use(logger());                           // "GET /users/42 200 1ms"
app.use(cors());                             // wide open (dev only)
app.use(cors(origin: 'https://app.example.com'));
app.use(cors(                                // credentialed allow-list
  origins: ['https://app.example.com'],
  credentials: true,
));
app.use(serveStatic('public'));              // static files, traversal-safe
```

- `cors()` answers browser pre-flights automatically and refuses the insecure
  `credentials: true` + wildcard-origin combination with an `ArgumentError`;
  use the `origins` allow-list for credentialed access.
- `serveStatic` serves `index.html` for directories, falls through to routes
  on a miss, and rejects `..`/symlink path traversal with `403`.

---

## Dev tools

A built-in development dashboard that tracks your API as you build it: recent
requests (method, path, status, timing, headers, bodies), aggregate stats, the
live route table and server info.

```dart
app.useDevTools();   // scaffolded apps have this wired already
```

Open `http://localhost:3000/__dev` — auto-refreshing, click any request to
inspect it; JSON snapshot at `/__dev/api`, programmatic access via
`app.devTools?.snapshot()`.

> **Development only.** The dashboard exposes request headers and bodies, so
> it never mounts when `DART_SERVER_ENV` / `DART_ENV` / `ENV` holds a
> production-like value — `production`, `prod`, `staging`, or `release`
> (case-insensitive); `dart_server prod` sets that for you. An unset variable
> means development (the `NODE_ENV` convention). Override with
> `useDevTools(enabled: ...)`.

---

## Using it as a library

Not using the CLI? Add the dependency and import it directly:

```sh
dart pub add dart_server
```

```dart
import 'package:dart_server/dart_server.dart';
```

Requires Dart SDK `^3.0.0`. This repository ships a runnable example in the
scaffold's layout — `dart run example/main.dart` — plus the framework's own
test suite (`dart test`).

---

## License

[MIT](LICENSE)
