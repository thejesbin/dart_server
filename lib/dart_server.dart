/// dart_server — a lightweight, Express.js-like HTTP server framework for Dart.
///
/// Build REST APIs with familiar routing, middleware and JSON helpers, using
/// only the Dart SDK (`dart:io` + `dart:convert`) — zero external runtime
/// dependencies.
///
/// ```dart
/// import 'package:dart_server/dart_server.dart';
///
/// void main() async {
///   final app = DartServer();
///
///   app.use(logger());
///
///   app.get('/', (req) => Response.text('Hello World'));
///   app.get('/users/:id', (req) => Response.json({'id': req.params['id']}));
///   app.post('/login', (req) async {
///     final body = await req.json();
///     return Response.json({'token': 'abc'});
///   });
///
///   await app.listen(3000);
/// }
/// ```
library dart_server;

export 'src/controller.dart' show Controller, RouteRegistrar, RouteEntry;
export 'src/dev_tools.dart' show DevTools, RequestRecord;
export 'src/errors.dart';
export 'src/factory.dart' show DartServerFactory;
export 'src/middleware.dart' show Handler, Next, Middleware, ErrorHandler, logger, cors, serveStatic;
export 'src/module.dart'
    show Module, Provider, ProviderScope, ControllerFactory, Injector, DiError, OnInit;
export 'src/request.dart';
export 'src/response.dart';
export 'src/server.dart';
