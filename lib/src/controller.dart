import 'exception_filter.dart';
import 'guard.dart';
import 'middleware.dart';

/// A single route declared by a [Controller]: an HTTP [method], a [path]
/// relative to the controller's [Controller.basePath], its [handler], and any
/// route-scoped [guards], [middleware], [interceptors] and [filters].
class RouteEntry {
  /// Creates a route entry; the scoped lists default to empty.
  RouteEntry(
    this.method,
    this.path,
    this.handler, {
    this.guards = const [],
    this.middleware = const [],
    this.interceptors = const [],
    this.filters = const [],
  });

  /// Upper-case HTTP method, e.g. `GET`.
  final String method;

  /// Path relative to the controller base path, e.g. `/:id`.
  final String path;

  /// The handler to run.
  final Handler handler;

  /// Guards that must pass for this route only.
  final List<Guard> guards;

  /// Middleware wrapping this route only (runs before guards).
  final List<Middleware> middleware;

  /// Interceptors wrapping this route's handler (run after guards).
  final List<Middleware> interceptors;

  /// Exception filters for this route only.
  final List<ExceptionFilter> filters;
}

/// Collects the routes a [Controller] declares in [Controller.register].
///
/// Paths are relative to the controller's [Controller.basePath]; the framework
/// joins them when mounting. Each verb accepts optional route-scoped
/// [Guard]s, [Middleware], interceptors and [ExceptionFilter]s:
///
/// ```dart
/// @override
/// void register(RouteRegistrar routes) {
///   routes.get('/', index);
///   routes.get('/:id', show);
///   routes.post('/', create, guards: [AdminGuard()]);
/// }
/// ```
class RouteRegistrar {
  /// The routes registered so far, in declaration order.
  final List<RouteEntry> entries = [];

  void _add(
    String method,
    String path,
    Handler handler,
    List<Guard> guards,
    List<Middleware> middleware,
    List<Middleware> interceptors,
    List<ExceptionFilter> filters,
  ) {
    entries.add(RouteEntry(
      method,
      path,
      handler,
      guards: guards,
      middleware: middleware,
      interceptors: interceptors,
      filters: filters,
    ));
  }

  /// Registers a `GET` route.
  void get(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('GET', path, handler, guards, middleware, interceptors, filters);

  /// Registers a `POST` route.
  void post(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('POST', path, handler, guards, middleware, interceptors, filters);

  /// Registers a `PUT` route.
  void put(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('PUT', path, handler, guards, middleware, interceptors, filters);

  /// Registers a `DELETE` route.
  void delete(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('DELETE', path, handler, guards, middleware, interceptors, filters);

  /// Registers a `PATCH` route.
  void patch(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('PATCH', path, handler, guards, middleware, interceptors, filters);

  /// Registers a `HEAD` route.
  void head(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('HEAD', path, handler, guards, middleware, interceptors, filters);

  /// Registers an `OPTIONS` route.
  void options(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('OPTIONS', path, handler, guards, middleware, interceptors, filters);

  /// Registers a route matching any method.
  void all(
    String path,
    Handler handler, {
    List<Guard> guards = const [],
    List<Middleware> middleware = const [],
    List<Middleware> interceptors = const [],
    List<ExceptionFilter> filters = const [],
  }) =>
      _add('ALL', path, handler, guards, middleware, interceptors, filters);
}

/// Base class for a controller — a cohesive group of routes under a common
/// [basePath], with its dependencies injected via the constructor.
///
/// Per-request behavior can be layered on without touching the handlers by
/// overriding [guards], [middleware], [interceptors] and [filters]. Together
/// with the route-level equivalents, each request to a controller route flows
/// through:
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
/// [basePath], [register] and the scoped lists are read **once**, when the
/// controller is mounted by `DartServerFactory.create` — returning different
/// values per call has no effect after startup.
///
/// ```dart
/// class UsersController extends Controller {
///   UsersController(this._users);
///   final UsersService _users;
///
///   @override
///   String get basePath => '/users';
///
///   @override
///   List<Guard> get guards => [AuthGuard()];
///
///   @override
///   void register(RouteRegistrar routes) {
///     routes.get('/', index);
///     routes.get('/:id', show);
///   }
///
///   Future<Response> index(Request req) async =>
///       Response.json(await _users.all());
///
///   Future<Response> show(Request req) async =>
///       Response.json(await _users.find(req.paramInt('id')));
/// }
/// ```
abstract class Controller {
  /// A path prefix applied to every route this controller declares, e.g.
  /// `/users`. Defaults to `''` (mounted at the root).
  String get basePath => '';

  /// Guards applied to every route in this controller.
  List<Guard> get guards => const [];

  /// Middleware wrapping every route in this controller (runs before guards).
  List<Middleware> get middleware => const [];

  /// Interceptors wrapping every handler in this controller (run after
  /// guards, so they can rely on guard-established state like
  /// `req.context['user']`).
  List<Middleware> get interceptors => const [];

  /// Exception filters applied to every route in this controller.
  List<ExceptionFilter> get filters => const [];

  /// Declares this controller's routes on [routes].
  void register(RouteRegistrar routes);
}
