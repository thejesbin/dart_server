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
// Project scaffold
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

A [dart_server](https://pub.dev/packages/dart_server) application.

## Getting started

```sh
dart pub get
dart_server dev      # development: auto-restart + dashboard at /__dev
dart_server prod     # production
```

The dev dashboard is available at <http://localhost:3000/__dev>.

## Generate code

```sh
dart_server make:model User
dart_server make:repository User
dart_server make:controller User
dart_server make:resource Post   # model + repository + controller in one go
dart_server make:middleware Auth
dart_server make:service Billing
```

## Structure

```
bin/server.dart        entry point
lib/app.dart           app wiring (middleware + routes)
lib/routes/            route registration
lib/controllers/       request handlers
lib/models/            data models
lib/repositories/      data access
```
''', {'PKG': pkg});

String serverEntry(String pkg) => _render(r'''
import 'dart:io';

import 'package:__PKG__/app.dart';

/// Application entry point.
///
/// Prefer the dart_server CLI, which sets the environment and (in dev) restarts
/// on changes:
///
///   dart_server dev      # development
///   dart_server prod     # production
///
/// You can also run it directly: `dart run bin/server.dart`.
Future<void> main(List<String> args) async {
  final app = buildApp();
  final port =
      int.tryParse(Platform.environment['DART_SERVER_PORT'] ?? '') ?? 3000;
  await app.listen(port);
}
''', {'PKG': pkg});

String appDart(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

import 'routes/routes.dart';

/// Builds and configures the application.
DartServer buildApp() {
  final app = DartServer();

  // Development dashboard at /__dev — auto-disabled in production.
  app.useDevTools();

  // Global middleware.
  app.use(logger());
  app.use(cors());

  // Routes.
  registerRoutes(app);

  return app;
}
''', {'PKG': pkg});

String routesDart(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

import '../controllers/home_controller.dart';

/// Registers all application routes.
void registerRoutes(DartServer app) {
  final home = HomeController();

  app.get('/', home.index);
  app.get('/health', (req) => Response.json({'status': 'ok'}));
}
''', {'PKG': pkg});

String homeController(String pkg) => _render(r'''
import 'package:dart_server/dart_server.dart';

/// Handles requests to the application root.
class HomeController {
  Response index(Request req) {
    return Response.json({
      'app': '__PKG__',
      'message': 'Your dart_server app is running 🎉',
    });
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

String controllerFile(String className, String varName, String snake) =>
    _render(r'''
import 'package:dart_server/dart_server.dart';

/// HTTP handlers for __CLASS__ resources.
///
/// Wire these up in `lib/routes/routes.dart`:
///
///   final __VAR__ = __CLASS__Controller();
///   app.get('/__SNAKE__s', __VAR__.index);
///   app.get('/__SNAKE__s/:id', __VAR__.show);
///   app.post('/__SNAKE__s', __VAR__.store);
///   app.put('/__SNAKE__s/:id', __VAR__.update);
///   app.delete('/__SNAKE__s/:id', __VAR__.destroy);
class __CLASS__Controller {
  /// GET /__SNAKE__s
  Future<Response> index(Request req) async {
    return Response.json({'data': <Object>[]});
  }

  /// GET /__SNAKE__s/:id
  Future<Response> show(Request req) async {
    final id = req.params['id'];
    return Response.json({'id': id});
  }

  /// POST /__SNAKE__s
  Future<Response> store(Request req) async {
    final body = await req.json();
    return Response.status(201, {'created': body});
  }

  /// PUT /__SNAKE__s/:id
  Future<Response> update(Request req) async {
    final id = req.params['id'];
    final body = await req.json();
    return Response.json({'id': id, 'updated': body});
  }

  /// DELETE /__SNAKE__s/:id
  Future<Response> destroy(Request req) async {
    return Response.status(204);
  }
}
''', {'CLASS': className, 'VAR': varName, 'SNAKE': snake});

String repositoryFile(String className, String snake) => _render(r'''
import '../models/__SNAKE__.dart';

/// In-memory data access for [__CLASS__].
///
/// Swap the internals for a real database when you're ready — keep the method
/// signatures stable and callers won't need to change.
class __CLASS__Repository {
  final List<__CLASS__> _items = [];
  int _nextId = 1;

  Future<List<__CLASS__>> all() async => List.unmodifiable(_items);

  Future<__CLASS__?> find(int id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<__CLASS__> create(__CLASS__ model) async {
    final created = model.copyWith(id: _nextId++);
    _items.add(created);
    return created;
  }

  Future<bool> delete(int id) async {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    return _items.length != before;
  }
}
''', {'CLASS': className, 'SNAKE': snake});

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

String serviceFile(String className) => _render(r'''
/// __CLASS__ service — application/business logic for __CLASS__.
///
/// Inject the repositories/services it needs via the constructor.
class __CLASS__Service {
  const __CLASS__Service();

  // TODO: implement service methods.
}
''', {'CLASS': className});
