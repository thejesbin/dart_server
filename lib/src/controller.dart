import 'middleware.dart';

/// A single route declared by a [Controller]: an HTTP [method], a [path]
/// relative to the controller's [Controller.basePath], and its [handler].
class RouteEntry {
  RouteEntry(this.method, this.path, this.handler);

  /// Upper-case HTTP method, e.g. `GET`.
  final String method;

  /// Path relative to the controller base path, e.g. `/:id`.
  final String path;

  /// The handler to run.
  final Handler handler;
}

/// Collects the routes a [Controller] declares in [Controller.register].
///
/// Paths are relative to the controller's [Controller.basePath]; the framework
/// joins them when mounting.
///
/// ```dart
/// @override
/// void register(RouteRegistrar routes) {
///   routes.get('/', index);
///   routes.get('/:id', show);
///   routes.post('/', create);
/// }
/// ```
class RouteRegistrar {
  /// The routes registered so far, in declaration order.
  final List<RouteEntry> entries = [];

  void _add(String method, String path, Handler handler) =>
      entries.add(RouteEntry(method, path, handler));

  /// Registers a `GET` route.
  void get(String path, Handler handler) => _add('GET', path, handler);

  /// Registers a `POST` route.
  void post(String path, Handler handler) => _add('POST', path, handler);

  /// Registers a `PUT` route.
  void put(String path, Handler handler) => _add('PUT', path, handler);

  /// Registers a `DELETE` route.
  void delete(String path, Handler handler) => _add('DELETE', path, handler);

  /// Registers a `PATCH` route.
  void patch(String path, Handler handler) => _add('PATCH', path, handler);

  /// Registers a `HEAD` route.
  void head(String path, Handler handler) => _add('HEAD', path, handler);

  /// Registers an `OPTIONS` route.
  void options(String path, Handler handler) => _add('OPTIONS', path, handler);

  /// Registers a route matching any method.
  void all(String path, Handler handler) => _add('ALL', path, handler);
}

/// Base class for a controller — a cohesive group of routes under a common
/// [basePath], with its dependencies injected via the constructor.
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
///   void register(RouteRegistrar routes) {
///     routes.get('/', index);
///     routes.get('/:id', show);
///   }
///
///   Future<Response> index(Request req) async =>
///       Response.json(await _users.all());
///
///   Future<Response> show(Request req) async =>
///       Response.json(await _users.find(req.params['id']!));
/// }
/// ```
abstract class Controller {
  /// A path prefix applied to every route this controller declares, e.g.
  /// `/users`. Defaults to `''` (mounted at the root).
  String get basePath => '';

  /// Declares this controller's routes on [routes].
  void register(RouteRegistrar routes);
}
