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
library;

export 'src/controller.dart' show Controller, RouteRegistrar, RouteEntry;
export 'src/dev_tools.dart' show DevTools, RequestRecord;
export 'src/env.dart' show Env;
export 'src/errors.dart';
export 'src/exception_filter.dart' show ExceptionFilter;
export 'src/factory.dart' show DartServerFactory;
export 'src/guard.dart' show Guard;
export 'src/middleware.dart'
    show
        Handler,
        Next,
        Middleware,
        ErrorHandler,
        internalRequestMarker,
        logger,
        cors,
        serveStatic;
export 'src/module.dart'
    show
        Module,
        Provider,
        ProviderScope,
        ControllerFactory,
        Injector,
        DiError,
        OnInit,
        OnShutdown;
export 'src/openapi.dart'
    show
        ApiDoc,
        ApiParam,
        ApiBody,
        ApiResponse,
        ApiSchema,
        ApiSecurityScheme,
        DocumentedRoute,
        OpenApiGenerator;
export 'src/request.dart';
export 'src/response.dart';
export 'src/server.dart';
