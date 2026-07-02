/// File templates used by the `dart_server` CLI generators.
///
/// Templates are raw strings with `__PLACEHOLDER__` markers (so embedded Dart
/// `$` and `${}` pass through untouched); [_render] substitutes the markers.
library;

String _render(String template, Map<String, String> vars) {
  var out = template;
  for (final entry in vars.entries) {
    out = out.replaceAll('__${entry.key}__', entry.value);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Project scaffold (modular)
// ---------------------------------------------------------------------------

/// `pubspec.yaml` for a scaffolded app; [dependency] is the dart_server
/// dependency entry (hosted caret constraint or a `--local` path).
String projectPubspec(String pkg, String dependency) => _render(r'''
name: __PKG__
description: A dart_server application.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.0.0

dependencies:
__DEP__

dev_dependencies:
  lints: ^4.0.0
  test: ^1.24.0
''', {'PKG': pkg, 'DEP': dependency});

/// `.gitignore` for a scaffolded app.
String projectGitignore() => '''
.dart_tool/
.packages
pubspec.lock
build/

.idea/
.vscode/
*.iml

.DS_Store
.env
''';

/// `analysis_options.yaml` for a scaffolded app.
String projectAnalysisOptions() => '''
include: package:lints/recommended.yaml
''';

/// The scaffolded app's `README.md`.
String projectReadme(String pkg) => _render(r'''
# __PKG__

A [dart_server](https://pub.dev/packages/dart_server) application with a
modular architecture: features live in self-contained modules that declare
their own providers, controllers and exports.

## Getting started

```sh
dart pub get
dart_server dev      # development: auto-restart + dashboard at /__dev
dart_server prod     # production
```

The dev dashboard is available at `http://localhost:3000/__dev`.

## Generate a feature

```sh
dart_server make:resource Post   # model + repository + service + controller + module
```

Then register the module in `lib/app_module.dart`:

```dart
import 'modules/post/post_module.dart';

Module appModule() => Module(
      imports: [postModule()],
      ...
    );
```

Other generators: `make:module`, `make:controller`, `make:service`,
`make:repository`, `make:model`, `make:guard`, `make:interceptor`,
`make:filter`, `make:middleware`.

## Test

```sh
dart test
```

## Structure

```
bin/server.dart            entry point (bootstraps AppModule)
lib/app_module.dart        root module
lib/app_controller.dart    root controller
lib/app_service.dart       root service (injected into the controller)
lib/modules/<feature>/     feature modules (module + controller + service + ...)
lib/guards/                guards           (make:guard)
lib/interceptors/          interceptors     (make:interceptor)
lib/filters/               exception filters (make:filter)
lib/middleware/            cross-cutting middleware
test/                      unit + end-to-end tests
.env.example               configuration template (copy to .env)
```
''', {'PKG': pkg});

/// `bin/server.dart` — the scaffolded entry point: bootstraps the root
/// module, wires dev tools + logging + CORS, and enables shutdown hooks.
String serverEntry(String pkg) => _render(r'''
import 'dart:io';

import 'package:dart_server/dart_server.dart';

import 'package:__PKG__/app_module.dart';

/// Application entry point.
///
/// Prefer the dart_server CLI, which sets the environment and (in dev) restarts
/// on changes:
///
///   dart_server dev      # development
///   dart_server prod     # production
Future<void> main(List<String> args) async {
  final app = await DartServerFactory.create(appModule());

  // Development dashboard at /__dev — auto-disabled in production.
  app.useDevTools();
  app.use(logger());
  app.use(cors());

  // Run OnShutdown hooks (DB pools, etc.) on Ctrl-C / SIGTERM.
  app.enableShutdownHooks();

  final port =
      int.tryParse(Platform.environment['DART_SERVER_PORT'] ?? '') ?? 3000;
  await app.listen(port);
}
''', {'PKG': pkg});

/// `lib/app_module.dart` — the scaffolded root module (Env + AppService
/// providers, AppController).
String appModuleFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

import 'app_controller.dart';
import 'app_service.dart';

/// The root module.
///
/// As your app grows, generate features with `dart_server make:resource <Name>`
/// and import them here, e.g.:
///
///   import 'modules/post/post_module.dart';
///   Module appModule() => Module(
///         imports: [postModule()],
///         ...
///       );
Module appModule() => Module(
      providers: [
        // Configuration from .env + the process environment.
        Provider.singleton((i) => Env.load()),
        Provider.singleton((i) => AppService(i.get<Env>())),
      ],
      controllers: [(i) => AppController(i.get<AppService>())],
    );
''', {'PKG': pkg});

/// `lib/app_service.dart` — the scaffolded root service with Env injected.
String appServiceFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// Application-level business logic, with configuration injected.
class AppService {
  AppService(this._env);

  final Env _env;

  String hello() => 'Hello from ${_env.get('APP_NAME') ?? '__PKG__'}!';
}
''', {'PKG': pkg});

/// `lib/app_controller.dart` — the scaffolded root controller (`/`,
/// `/health`).
String appControllerFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

import 'app_service.dart';

/// Handles requests to the application root.
class AppController extends Controller {
  AppController(this._service);

  final AppService _service;

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.json({'message': _service.hello()}));
    routes.get('/health', (req) => Response.json({'status': 'ok'}));
  }
}
''', {'PKG': pkg});

/// `.env.example` — configuration template the user copies to `.env`.
String envExampleFile(String pkg) => _render(r'''
# Copy this file to `.env` for local configuration.
# Real environment variables always win over values in .env.

# APP_NAME=__PKG__
# DART_SERVER_PORT=3000
''', {'PKG': pkg});

/// `test/app_test.dart` — end-to-end test booting the real app on an
/// ephemeral port.
String testAppFile(String pkg) => _render(r'''
import 'dart:convert';
import 'dart:io';

import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

import 'package:__PKG__/app_module.dart';

/// End-to-end test: boots the real app on an ephemeral port and calls it
/// over HTTP.
void main() {
  late DartServer app;
  late HttpServer server;
  final client = HttpClient();

  setUp(() async {
    app = await DartServerFactory.create(appModule());
    server = await app.listen(0,
        address: InternetAddress.loopbackIPv4, quiet: true);
  });

  tearDown(() => app.close(force: true));

  Future<({int status, String body})> get(String path) async {
    final uri = Uri.parse('http://${server.address.host}:${server.port}$path');
    final response = await (await client.getUrl(uri)).close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  test('GET / greets', () async {
    final res = await get('/');
    expect(res.status, 200);
    expect(jsonDecode(res.body)['message'], contains('Hello'));
  });

  test('GET /health is ok', () async {
    final res = await get('/health');
    expect(res.status, 200);
    expect(jsonDecode(res.body), {'status': 'ok'});
  });
}
''', {'PKG': pkg});

/// `test/app_service_test.dart` — unit test showing constructor injection
/// with a fake Env.
String testAppServiceFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';
import 'package:test/test.dart';

import 'package:__PKG__/app_service.dart';

/// Unit test: constructor injection makes services trivial to test —
/// hand them a fake Env instead of the real environment.
void main() {
  test('hello() uses APP_NAME when configured', () {
    final service = AppService(Env.fromMap({'APP_NAME': 'Testing'}));
    expect(service.hello(), 'Hello from Testing!');
  });

  test('hello() falls back to the package name', () {
    final service = AppService(Env.fromMap({}));
    expect(service.hello(), 'Hello from __PKG__!');
  });
}
''', {'PKG': pkg});

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

/// `make:model` output — a plain model with `fromJson`/`toJson`/`copyWith`.
String modelFile(String className) => _render(r'''
/// __CLASS__ model.
class __CLASS__ {
  __CLASS__({
    this.id,
    required this.name,
  });

  final int? id;
  final String name;

  factory __CLASS__.fromJson(Map<String, dynamic> json) {
    return __CLASS__(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  __CLASS__ copyWith({int? id, String? name}) {
    return __CLASS__(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
''', {'CLASS': className});

/// Standalone controller (a [Controller] subclass with stub handlers).
/// `make:controller` output — a Controller subclass with REST handler stubs.
String controllerFile(String className, String snake) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// HTTP handlers for __CLASS__ resources.
///
/// Provide it from a module's `controllers`, e.g.:
///   controllers: [(i) => __CLASS__Controller()]
class __CLASS__Controller extends Controller {
  @override
  String get basePath => '/__SNAKE__s';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', index);
    routes.get('/:id', show);
    routes.post('/', store);
    routes.put('/:id', update);
    routes.delete('/:id', destroy);
  }

  Future<Response> index(Request req) async =>
      Response.json({'data': <Object>[]});

  Future<Response> show(Request req) async =>
      Response.json({'id': req.params['id']});

  Future<Response> store(Request req) async {
    final body = await req.json();
    return Response.status(201, {'created': body});
  }

  Future<Response> update(Request req) async {
    final body = await req.json();
    return Response.json({'id': req.params['id'], 'updated': body});
  }

  Future<Response> destroy(Request req) async => Response.status(204);
}
''', {'CLASS': className, 'SNAKE': snake});

/// Standalone service stub.
/// `make:service` output — an empty service class stub.
String serviceFile(String className) => _render(r'''
/// __CLASS__ service — application/business logic for __CLASS__.
///
/// Provide it from a module:
///   providers: [Provider.singleton((i) => __CLASS__Service())]
class __CLASS__Service {
  __CLASS__Service();

  // TODO: implement service methods.
}
''', {'CLASS': className});

/// Standalone repository (model-backed in-memory data access).
/// `make:repository` output — in-memory data access for a model.
String repositoryFile(String className, String snake) => _render(r'''
import '__SNAKE__.dart';

/// In-memory data access for [__CLASS__].
class __CLASS__Repository {
  final List<__CLASS__> _items = [];
  int _nextId = 1;

  List<__CLASS__> all() => List.unmodifiable(_items);

  __CLASS__? find(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  __CLASS__ create(__CLASS__ input) {
    final created = input.copyWith(id: _nextId++);
    _items.add(created);
    return created;
  }

  bool delete(int id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    return _items.length != before;
  }
}
''', {'CLASS': className, 'SNAKE': snake});

/// Standalone, minimal module (commented wiring to fill in).
/// `make:module` output — a minimal module with commented wiring to fill in.
String moduleFile(String className, String varName) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ module.
///
/// Register it in lib/app_module.dart:
///   Module appModule() => Module(imports: [__VAR__Module()], ...);
Module __VAR__Module() => Module(
      providers: [
        // Provider.singleton((i) => __CLASS__Service()),
      ],
      controllers: [
        // (i) => __CLASS__Controller(i.get<__CLASS__Service>()),
      ],
      // exports: [__CLASS__Service],
    );
''', {'CLASS': className, 'VAR': varName});

/// `make:middleware` output — a pass-through middleware stub.
String middlewareFile(String className, String varName) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ middleware.
///
/// Register it globally with `app.use(__VAR__Middleware());`, or scope it to a
/// controller (`List<Middleware> get middleware`) or a route
/// (`routes.get('/', handler, middleware: [...])`).
Middleware __VAR__Middleware() {
  return (req, next) async {
    // TODO: implement __CLASS__ middleware logic.
    return next();
  };
}
''', {'CLASS': className, 'VAR': varName});

/// `make:guard` output — a Guard implementation stub.
String guardFile(String className) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ guard — decides whether a request may proceed.
///
/// Attach it globally (`DartServerFactory.create(root, guards: [...])`), to a
/// controller (`List<Guard> get guards`) or to a route
/// (`routes.get('/', handler, guards: [__CLASS__Guard()])`).
///
/// Return `false` to reject with 403, or throw an HttpError for a different
/// status (e.g. `HttpError.unauthorized()`). Use `req.context` to pass what
/// the guard learns (e.g. the authenticated user) on to the handler.
class __CLASS__Guard implements Guard {
  @override
  Future<bool> canActivate(Request req) async {
    // TODO: implement __CLASS__ guard logic.
    return true;
  }
}
''', {'CLASS': className});

/// `make:interceptor` output — an interceptor (middleware-shaped) stub.
String interceptorFile(String className, String varName) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ interceptor — wraps handler execution, after guards have passed.
///
/// Attach it globally (`DartServerFactory.create(root, interceptors: [...])`),
/// to a controller (`List<Middleware> get interceptors`) or to a route
/// (`routes.get('/', handler, interceptors: [__VAR__Interceptor()])`).
Middleware __VAR__Interceptor() {
  return (req, next) async {
    // Before the handler runs (guards have already passed).
    final res = await next();
    // After the handler — inspect or transform the response.
    return res;
  };
}
''', {'CLASS': className, 'VAR': varName});

/// `make:filter` output — an ExceptionFilter implementation stub.
String filterFile(String className) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ exception filter — converts errors into responses.
///
/// Attach it globally (`DartServerFactory.create(root, filters: [...])`), to a
/// controller (`List<ExceptionFilter> get filters`) or to a route
/// (`routes.get('/', handler, filters: [__CLASS__Filter()])`).
///
/// Return a Response to handle the error, or `null` to let the next filter
/// (or the framework default) deal with it.
class __CLASS__Filter implements ExceptionFilter {
  @override
  Response? handle(Request req, Object error, StackTrace stackTrace) {
    // TODO: select the errors this filter owns with an `is` check.
    // if (error is MyDomainError) {
    //   return Response.json({'error': error.message}, status: 422);
    // }
    return null;
  }
}
''', {'CLASS': className});

// ---------------------------------------------------------------------------
// Resource (full feature: model + repository + service + controller + module)
// ---------------------------------------------------------------------------

/// `make:resource` repository — in-memory storage backing the service.
String resourceRepositoryFile(String className, String snake) => _render(r'''
import '__SNAKE__.dart';

/// In-memory data access for [__CLASS__].
class __CLASS__Repository {
  final List<__CLASS__> _items = [];
  int _nextId = 1;

  List<__CLASS__> all() => List.unmodifiable(_items);

  __CLASS__? find(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  __CLASS__ create(__CLASS__ input) {
    final created = input.copyWith(id: _nextId++);
    _items.add(created);
    return created;
  }

  bool delete(int id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    return _items.length != before;
  }
}
''', {'CLASS': className, 'SNAKE': snake});

/// `make:resource` service — business logic delegating to the repository.
String resourceServiceFile(String className, String snake) => _render(r'''
import '__SNAKE__.dart';
import '__SNAKE___repository.dart';

/// Business logic for [__CLASS__], delegating storage to [__CLASS__Repository].
class __CLASS__Service {
  __CLASS__Service(this._repository);

  final __CLASS__Repository _repository;

  List<__CLASS__> all() => _repository.all();

  __CLASS__? find(int id) => _repository.find(id);

  __CLASS__ create(__CLASS__ input) => _repository.create(input);

  bool delete(int id) => _repository.delete(id);
}
''', {'CLASS': className, 'SNAKE': snake});

/// `make:resource` controller — REST routes backed by the service.
String resourceControllerFile(String className, String snake) => _render(r'''
import 'package:dart_server/dart_server.dart';

import '__SNAKE__.dart';
import '__SNAKE___service.dart';

/// HTTP handlers for __CLASS__ resources, backed by [__CLASS__Service].
class __CLASS__Controller extends Controller {
  __CLASS__Controller(this._service);

  final __CLASS__Service _service;

  @override
  String get basePath => '/__SNAKE__s';

  @override
  void register(RouteRegistrar routes) {
    routes.get('/', index);
    routes.get('/:id', show);
    routes.post('/', store);
    routes.delete('/:id', destroy);
  }

  Future<Response> index(Request req) async => Response.json(
      {'data': _service.all().map((item) => item.toJson()).toList()});

  Future<Response> show(Request req) async {
    final item = _service.find(_id(req));
    if (item == null) throw HttpError.notFound('__CLASS__ not found');
    return Response.json(item.toJson());
  }

  Future<Response> store(Request req) async {
    final body = await req.json() as Map<String, dynamic>;
    final created = _service.create(__CLASS__.fromJson(body));
    return Response.status(201, created.toJson());
  }

  Future<Response> destroy(Request req) async {
    if (!_service.delete(_id(req))) {
      throw HttpError.notFound('__CLASS__ not found');
    }
    return Response.status(204);
  }

  int _id(Request req) => int.tryParse(req.params['id'] ?? '') ?? -1;
}
''', {'CLASS': className, 'SNAKE': snake});

/// `make:resource` module — wires repository, service and controller, and
/// exports the service.
String resourceModuleFile(String className, String varName, String snake) =>
    _render(r'''
import 'package:dart_server/dart_server.dart';

import '__SNAKE___controller.dart';
import '__SNAKE___repository.dart';
import '__SNAKE___service.dart';

/// __CLASS__ feature module. Add `__VAR__Module()` to your AppModule imports.
Module __VAR__Module() => Module(
      providers: [
        Provider.singleton((i) => __CLASS__Repository()),
        Provider.singleton((i) => __CLASS__Service(i.get<__CLASS__Repository>())),
      ],
      controllers: [
        (i) => __CLASS__Controller(i.get<__CLASS__Service>()),
      ],
      exports: [__CLASS__Service],
    );
''', {'CLASS': className, 'VAR': varName, 'SNAKE': snake});
