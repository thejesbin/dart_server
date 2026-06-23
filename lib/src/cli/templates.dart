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
''', {'PKG': pkg, 'DEP': dependency});

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

String projectAnalysisOptions() => '''
include: package:lints/recommended.yaml
''';

String projectReadme(String pkg) => _render(r'''
# __PKG__

A [dart_server](https://pub.dev/packages/dart_server) application with a
NestJS-style modular architecture.

## Getting started

```sh
dart pub get
dart_server dev      # development: auto-restart + dashboard at /__dev
dart_server prod     # production
```

The dev dashboard is available at <http://localhost:3000/__dev>.

## Generate a feature

```sh
dart_server make:resource Post   # model + repository + service + controller + module
```

Then register the module in `lib/app_module.dart`:

```dart
import 'modules/post/post_module.dart';

Module appModule() => Module(
      imports: [postModule()],
      controllers: [(i) => AppController()],
    );
```

Other generators: `make:module`, `make:controller`, `make:service`,
`make:repository`, `make:model`, `make:middleware`.

## Structure

```
bin/server.dart            entry point (bootstraps AppModule)
lib/app_module.dart        root module
lib/app_controller.dart    root controller
lib/modules/<feature>/     feature modules (module + controller + service + ...)
lib/middleware/            cross-cutting middleware
```
''', {'PKG': pkg});

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

  final port =
      int.tryParse(Platform.environment['DART_SERVER_PORT'] ?? '') ?? 3000;
  await app.listen(port);
}
''', {'PKG': pkg});

String appModuleFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

import 'app_controller.dart';

/// The root module.
///
/// As your app grows, import feature modules here, e.g.:
///
///   import 'modules/post/post_module.dart';
///   Module appModule() => Module(
///         imports: [postModule()],
///         controllers: [(i) => AppController()],
///       );
Module appModule() => Module(
      controllers: [(i) => AppController()],
    );
''', {'PKG': pkg});

String appControllerFile(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// Handles requests to the application root.
class AppController extends Controller {
  @override
  void register(RouteRegistrar routes) {
    routes.get('/', (req) => Response.json({
          'app': '__PKG__',
          'message': 'Your dart_server app is running 🎉',
        }));
    routes.get('/health', (req) => Response.json({'status': 'ok'}));
  }
}
''', {'PKG': pkg});

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

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

String middlewareFile(String className, String varName) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// __CLASS__ middleware.
///
/// Register it globally with `app.use(__VAR__Middleware());`.
Middleware __VAR__Middleware() {
  return (req, next) async {
    // TODO: implement __CLASS__ middleware logic.
    return next();
  };
}
''', {'CLASS': className, 'VAR': varName});

// ---------------------------------------------------------------------------
// Resource (full feature: model + repository + service + controller + module)
// ---------------------------------------------------------------------------

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
