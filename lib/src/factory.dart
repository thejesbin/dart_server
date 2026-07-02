import 'dart:io';

import 'controller.dart';
import 'di_container.dart';
import 'errors.dart';
import 'exception_filter.dart';
import 'guard.dart';
import 'middleware.dart';
import 'module.dart';
import 'request.dart';
import 'server.dart';

/// Bootstraps a [DartServer] from a root [Module].
///
/// It builds the module graph, wires dependency injection (with per-module
/// encapsulation), instantiates providers and controllers, runs [OnInit]
/// hooks, and mounts every controller's routes under its `basePath` with the
/// full request pipeline composed around each handler:
///
/// ```text
/// global middleware (app.use)
///   -> controller middleware -> route middleware
///     -> guards        (global -> controller -> route)
///       -> interceptors (global -> controller -> route)
///         -> handler
///   errors from guards/interceptors/handler
///     -> filters       (route -> controller -> global)
///       -> built-in mapping (onError, HttpError, 500)
/// ```
///
/// Providers and controllers implementing [OnShutdown] are torn down (in
/// reverse creation order) when the returned app's `close()` runs — call
/// `app.enableShutdownHooks()` to also trigger that on SIGINT/SIGTERM.
///
/// ```dart
/// Future<void> main() async {
///   final app = await DartServerFactory.create(appModule());
///   app.use(logger());
///   app.enableShutdownHooks();
///   await app.listen(3000);
/// }
/// ```
class DartServerFactory {
  DartServerFactory._();

  /// Creates and configures a [DartServer] from [rootModule].
  ///
  /// * [guards] run for every controller route, before controller/route
  ///   guards. They do not apply to `404`s, to the dev dashboard, or to routes
  ///   added directly on the returned [DartServer].
  /// * [interceptors] wrap every controller handler, after guards.
  /// * [filters] are the last-resort exception filters, tried after route and
  ///   controller filters.
  /// * [maxBodyBytes] is forwarded to the [DartServer] constructor.
  static Future<DartServer> create(
    Module rootModule, {
    int maxBodyBytes = 1024 * 1024,
    List<Guard> guards = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) async {
    final container = ModuleContainer(rootModule);
    final controllers = await container.bootstrap();

    final app = DartServer(maxBodyBytes: maxBodyBytes);
    for (final controller in controllers) {
      final registrar = RouteRegistrar();
      controller.register(registrar);
      // Controller-scoped members are read exactly once, at mount time.
      final basePath = controller.basePath;
      final controllerGuards = controller.guards;
      final controllerMiddleware = controller.middleware;
      final controllerInterceptors = controller.interceptors;
      final controllerFilters = controller.filters;
      for (final entry in registrar.entries) {
        app.route(
          entry.method,
          joinPaths(basePath, entry.path),
          _compose(
            entry,
            guards: [...guards, ...controllerGuards, ...entry.guards],
            middleware: [...controllerMiddleware, ...entry.middleware],
            interceptors: [
              ...interceptors,
              ...controllerInterceptors,
              ...entry.interceptors,
            ],
            // Most specific first: route -> controller -> global.
            filters: [...entry.filters, ...controllerFilters, ...filters],
          ),
        );
      }
    }

    // Tear down OnShutdown providers/controllers when the app closes,
    // dependents before their dependencies. One failing hook must not stop
    // the rest of the teardown.
    final lifecycle = container.lifecycleInstances;
    app.addShutdownHook(() async {
      for (final instance in lifecycle.reversed) {
        if (instance is! OnShutdown) continue;
        try {
          await instance.onShutdown();
        } catch (error, stackTrace) {
          stderr.writeln(
              'onShutdown failed for ${instance.runtimeType}: $error\n$stackTrace');
        }
      }
    });

    return app;
  }

  /// Composes one route's scoped pipeline into a plain [Handler]:
  /// `middleware(filters(guards -> interceptors -> handler))`.
  ///
  /// The filter zone wraps guards, interceptors and the handler; scoped
  /// middleware sits outside it, so an error thrown by the middleware itself
  /// is never intercepted by the route's filters. An error no filter handles
  /// rethrows and is converted by the framework's built-in mapping, so global
  /// middleware still observe the resulting error response.
  static Handler _compose(
    RouteEntry entry, {
    required List<Guard> guards,
    required List<Middleware> middleware,
    required List<Middleware> interceptors,
    required List<ExceptionFilter> filters,
  }) {
    // Innermost: interceptors around the handler (first listed = outermost).
    Handler handler = entry.handler;
    for (final interceptor in interceptors.reversed) {
      handler = _wrap(interceptor, handler);
    }

    // Guards gate everything inside the filter zone.
    final guarded = guards.isEmpty
        ? handler
        : (Request req) async {
            for (final guard in guards) {
              if (!await guard.canActivate(req)) {
                throw HttpError.forbidden();
              }
            }
            return handler(req);
          };

    // Exception filters: first non-null response wins, otherwise rethrow.
    final filtered = filters.isEmpty
        ? guarded
        : (Request req) async {
            try {
              return await guarded(req);
            } catch (error, stackTrace) {
              for (final filter in filters) {
                final response = await filter.handle(req, error, stackTrace);
                if (response != null) return response;
              }
              rethrow;
            }
          };

    // Outermost: scoped middleware (first listed = outermost).
    Handler composed = filtered;
    for (final m in middleware.reversed) {
      composed = _wrap(m, composed);
    }
    return composed;
  }

  static Handler _wrap(Middleware middleware, Handler next) =>
      (req) => middleware(req, () => next(req));

  /// Joins a controller [base] path with a route [path], collapsing slashes.
  ///
  /// `('/users', '/:id') -> '/users/:id'`, `('', '/health') -> '/health'`,
  /// `('/users', '/') -> '/users'`.
  static String joinPaths(String base, String path) {
    final left = base.trim();
    final right = path.trim();
    // A bare '/' base means "mounted at the root" — treat it as empty so
    // ('/', '/health') yields '/health', not '//health'.
    final trimmedLeft = left == '/'
        ? ''
        : (left.endsWith('/') && left.length > 1)
            ? left.substring(0, left.length - 1)
            : left;
    final hasRight = right.isNotEmpty && right != '/';
    final normalizedRight =
        hasRight ? (right.startsWith('/') ? right : '/$right') : '';
    final joined = '$trimmedLeft$normalizedRight';
    if (joined.isEmpty) return '/';
    return joined.startsWith('/') ? joined : '/$joined';
  }
}
