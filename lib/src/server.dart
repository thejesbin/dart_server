import 'dart:async';
import 'dart:io';

import 'dev_tools.dart';
import 'errors.dart';
import 'middleware.dart';
import 'request.dart';
import 'response.dart';
import 'router.dart';

/// An Express.js-style HTTP server.
///
/// Register middleware with [use], routes with [get]/[post]/[put]/[delete]
/// (and friends), then call [listen]:
///
/// ```dart
/// final app = DartServer();
///
/// app.use(logger());
///
/// app.get('/', (req) => Response.text('Hello World'));
/// app.get('/users/:id', (req) => Response.json({'id': req.params['id']}));
/// app.post('/login', (req) async {
///   final body = await req.json();
///   return Response.json({'token': 'abc'});
/// });
///
/// await app.listen(3000);
/// ```
class DartServer {
  /// Maximum accepted request-body size in bytes. A larger body is rejected
  /// with `413 Payload Too Large` before any handler runs, guarding against
  /// memory-exhaustion. Pass `0` (or a negative value) to disable the limit.
  /// Defaults to 1 MiB.
  final int maxBodyBytes;

  /// Creates a server.
  ///
  /// [maxBodyBytes] caps the request-body size (default 1 MiB; `0` disables).
  DartServer({this.maxBodyBytes = 1024 * 1024});

  final Router _router = Router();
  final List<Middleware> _middlewares = [];
  final List<Future<void> Function()> _shutdownHooks = [];
  final List<StreamSubscription<ProcessSignal>> _signalSubscriptions = [];
  // Memoized teardown future: all close() callers share one teardown run.
  Future<void>? _closing;
  // Requests currently inside _handleRequest, and the completer a graceful
  // close awaits until they drain.
  int _inFlight = 0;
  Completer<void>? _idle;
  ErrorHandler? _errorHandler;
  HttpServer? _httpServer;
  DevTools? _devTools;

  /// The active [DevTools] collector once [useDevTools] has enabled it,
  /// otherwise `null`. Useful for inspecting recorded requests in tests.
  DevTools? get devTools => _devTools;

  /// The underlying [HttpServer] once [listen] has been called, otherwise
  /// `null`.
  HttpServer? get server => _httpServer;

  /// The port the server is bound to, or `null` if it isn't listening.
  int? get port => _httpServer?.port;

  /// Registers a global [Middleware]. Middleware runs in registration order,
  /// wrapping the matched route handler.
  void use(Middleware middleware) => _middlewares.add(middleware);

  /// Registers a [handler] for `GET` requests to [path].
  void get(String path, Handler handler) => _router.add('GET', path, handler);

  /// Registers a [handler] for `POST` requests to [path].
  void post(String path, Handler handler) => _router.add('POST', path, handler);

  /// Registers a [handler] for `PUT` requests to [path].
  void put(String path, Handler handler) => _router.add('PUT', path, handler);

  /// Registers a [handler] for `DELETE` requests to [path].
  void delete(String path, Handler handler) =>
      _router.add('DELETE', path, handler);

  /// Registers a [handler] for `PATCH` requests to [path].
  void patch(String path, Handler handler) =>
      _router.add('PATCH', path, handler);

  /// Registers a [handler] for `HEAD` requests to [path].
  void head(String path, Handler handler) => _router.add('HEAD', path, handler);

  /// Registers a [handler] for `OPTIONS` requests to [path].
  void options(String path, Handler handler) =>
      _router.add('OPTIONS', path, handler);

  /// Registers a [handler] for [path] regardless of HTTP method.
  void all(String path, Handler handler) => _router.add('ALL', path, handler);

  /// Registers a [handler] for an arbitrary [method] and [path].
  ///
  /// A lower-level escape hatch behind the verb methods above; also used by
  /// `DartServerFactory` to mount controller routes.
  void route(String method, String path, Handler handler) =>
      _router.add(method, path, handler);

  /// Sets a custom [ErrorHandler] invoked for any uncaught error. If it is
  /// `null` (the default) the framework's built-in handler is used, which maps
  /// [HttpError] to its status code and everything else to `500`.
  void onError(ErrorHandler handler) => _errorHandler = handler;

  /// Mounts an in-memory development dashboard at [path] (default `/__dev`)
  /// that tracks recent API requests, aggregate stats, the route table and
  /// server info — handy while building and debugging.
  ///
  /// **Development only.** Unless [enabled] is given explicitly, the dashboard
  /// is disabled when a production environment is detected: when
  /// `DART_SERVER_ENV` / `DART_ENV` / `ENV` is a production-like value
  /// (`production`, `prod`, `staging`, `release`). When that variable is unset
  /// it is treated as development (the same convention as Node's `NODE_ENV`),
  /// so it works out of the box under `dart run`. Because the dashboard exposes
  /// request headers and bodies, **set `DART_SERVER_ENV=production` (or pass
  /// `enabled: false`) in production deployments.**
  ///
  /// ```dart
  /// final app = DartServer();
  /// app.useDevTools();            // visit http://localhost:3000/__dev
  /// ```
  ///
  /// Returns `true` if the dashboard was mounted.
  bool useDevTools({
    String path = '/__dev',
    int maxRequests = 100,
    bool captureBodies = true,
    bool? enabled,
  }) {
    final active = enabled ?? !_isProductionEnvironment();
    if (!active) return false;

    final dev = DevTools(
      dashboardPath: path,
      maxRequests: maxRequests,
      captureBodies: captureBodies,
      routesProvider: () => _router.registeredRoutes,
      portProvider: () => _httpServer?.port,
    );
    _devTools = dev;
    // Outermost, so it observes the final response regardless of call order.
    _middlewares.insert(0, dev.middleware);
    get(path, dev.dashboardHandler);
    get('$path/api', dev.apiHandler);
    post('$path/api/clear', dev.clearHandler);
    stdout.writeln('dart_server dev tools mounted at $path '
        '(development only — disable in production)');
    return true;
  }

  /// Whether an explicit production-like environment variable is set.
  ///
  /// Checks `DART_SERVER_ENV` / `DART_ENV` / `ENV`; an unset/empty value is
  /// treated as development.
  static bool _isProductionEnvironment() {
    final env = Platform.environment['DART_SERVER_ENV'] ??
        Platform.environment['DART_ENV'] ??
        Platform.environment['ENV'];
    if (env == null || env.isEmpty) return false;
    final value = env.toLowerCase();
    return value == 'production' ||
        value == 'prod' ||
        value == 'staging' ||
        value == 'release';
  }

  /// Binds to [address]:[port] and starts serving requests.
  ///
  /// [address] accepts a host string (e.g. `'127.0.0.1'`), an
  /// [InternetAddress], or `null` to listen on all IPv4 interfaces. Pass
  /// `port: 0` to bind an ephemeral port (handy in tests — read it back from
  /// [port]).
  ///
  /// Returns the bound [HttpServer]. The future completes once the socket is
  /// listening.
  ///
  /// By default a one-line startup banner is printed to stdout. Pass
  /// [quiet] `true` to suppress it, or [onReady] to run your own startup logic
  /// instead (which also suppresses the banner).
  Future<HttpServer> listen(
    int port, {
    Object? address,
    bool quiet = false,
    void Function(HttpServer server)? onReady,
  }) async {
    final bindAddress = address ?? InternetAddress.anyIPv4;
    final httpServer = await HttpServer.bind(bindAddress, port);
    _httpServer = httpServer;
    httpServer.listen(_handleRequest);
    if (onReady != null) {
      onReady(httpServer);
    } else if (!quiet) {
      stdout.writeln('dart_server listening on '
          'http://${httpServer.address.host}:${httpServer.port}');
    }
    return httpServer;
  }

  /// Registers a [hook] to run when the server [close]s.
  ///
  /// Hooks run once, in reverse registration order (last registered, first
  /// run). A hook that throws is logged to stderr and does not prevent the
  /// remaining hooks from running. `DartServerFactory` uses this to run
  /// `OnShutdown` lifecycle hooks on providers and controllers.
  void addShutdownHook(Future<void> Function() hook) =>
      _shutdownHooks.add(hook);

  /// Runs shutdown hooks on SIGINT/SIGTERM (Ctrl-C, container stop), so the
  /// process can release resources cleanly instead of dying mid-request.
  ///
  /// The first signal triggers a graceful [close]: the server stops accepting
  /// connections, waits for in-flight requests to finish, then runs all
  /// shutdown hooks (including `OnShutdown` providers). A **second** signal
  /// escalates: active connections are destroyed, the wait is abandoned, and
  /// signal interception is removed — so a third signal terminates the process
  /// with Dart's default behavior. Without calling this, hooks only run when
  /// you call [close] yourself.
  ///
  /// Calling it more than once has no effect. SIGTERM is not watchable on
  /// Windows and is skipped there.
  void enableShutdownHooks() {
    if (_signalSubscriptions.isNotEmpty) return;
    final signals = [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ];
    for (final signal in signals) {
      _signalSubscriptions.add(signal.watch().listen((_) {
        if (_closing == null) {
          // First signal: graceful shutdown. Never let an error escape as an
          // uncaught async error from the signal callback.
          close().catchError((Object error, StackTrace stackTrace) {
            stderr.writeln('Shutdown failed: $error\n$stackTrace');
          });
        } else {
          // Second signal: force. Destroy connections, unblock the drain,
          // and stop intercepting signals (a third signal then terminates).
          final subscriptions = List.of(_signalSubscriptions);
          _signalSubscriptions.clear();
          for (final subscription in subscriptions) {
            subscription.cancel();
          }
          _httpServer?.close(force: true);
          _idle?.complete();
          _idle = null;
        }
      }));
    }
  }

  /// Stops the server from accepting new connections, waits for in-flight
  /// requests to finish (unless [force] is `true`, which destroys their
  /// connections immediately), then runs shutdown hooks (see
  /// [addShutdownHook]) exactly once.
  ///
  /// Safe to call multiple times and from concurrent callers — every call
  /// shares the same teardown future. Note that [force] only takes effect on
  /// the first call.
  Future<void> close({bool force = false}) => _closing ??= _doClose(force);

  Future<void> _doClose(bool force) async {
    // Stop intercepting signals early; snapshot first so a concurrent
    // escalation handler can't race the iteration.
    final subscriptions = List.of(_signalSubscriptions);
    _signalSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }

    // Stop accepting new connections. HttpServer.close(force: false) does NOT
    // wait for in-flight requests — that's what the drain below is for.
    final server = _httpServer;
    if (server != null) await server.close(force: force);

    // Drain: wait until every request currently in _handleRequest completes.
    if (!force && _inFlight > 0) {
      final completer = Completer<void>();
      _idle = completer;
      if (_inFlight > 0) await completer.future;
      _idle = null;
    }
    _httpServer = null;

    for (final hook in _shutdownHooks.reversed) {
      try {
        await hook();
      } catch (error, stackTrace) {
        stderr.writeln('Shutdown hook failed: $error\n$stackTrace');
      }
    }
  }

  /// Reads the request, runs it through the chain and writes the response.
  Future<void> _handleRequest(HttpRequest httpRequest) async {
    _inFlight++;
    try {
      Request? req;
      try {
        req = await Request.from(httpRequest,
            maxBodyBytes: maxBodyBytes > 0 ? maxBodyBytes : null);
        final response = await _runChain(req);
        await response.writeTo(httpRequest.response,
            head: req.method == 'HEAD');
      } catch (error, stackTrace) {
        // Reached only for errors thrown outside the route handler (e.g. body
        // buffering / 413, or a middleware that throws before/after next()).
        final response = await _resolveError(req, error, stackTrace);
        try {
          await response.writeTo(httpRequest.response,
              head: req?.method == 'HEAD');
        } catch (_) {
          // The response was already (partially) sent; nothing more we can do.
        }
      }
    } finally {
      _inFlight--;
      if (_inFlight == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Composes the middleware stack around the matched route handler and runs
  /// it. Middleware at index `i` receives a `next` that invokes index `i + 1`,
  /// and the final `next` runs the route itself.
  ///
  /// Errors from the route handler are converted to a [Response] at the leaf,
  /// so they flow back *out* through the middleware chain — middleware (and the
  /// built-in [logger]/[cors]) therefore observe error responses just like
  /// successful ones.
  Future<Response> _runChain(Request req) {
    FutureOr<Response> dispatch(int index) {
      if (index < _middlewares.length) {
        return _middlewares[index](req, () => dispatch(index + 1));
      }
      return _runRouteGuarded(req);
    }

    return Future.sync(() => dispatch(0));
  }

  /// Runs the matched route, turning any thrown error into a [Response] in
  /// place so it propagates back through the middleware chain.
  Future<Response> _runRouteGuarded(Request req) async {
    try {
      return await _runRoute(req);
    } catch (error, stackTrace) {
      return _resolveError(req, error, stackTrace);
    }
  }

  /// Matches and runs the route for [req], or returns a `404`/`405` response.
  FutureOr<Response> _runRoute(Request req) {
    final match = _router.match(req.method, req.path);
    if (match == null) {
      final allowed = _router.allowedMethods(req.path);
      if (allowed.isNotEmpty) {
        return Response.json(
          {'error': 'Method Not Allowed', 'method': req.method},
          status: 405,
        ).header('Allow', allowed.join(', '));
      }
      return Response.json(
        {'error': 'Not Found', 'path': req.path},
        status: 404,
      );
    }
    req.params = match.params;
    return match.handler(req);
  }

  /// Turns an uncaught [error] into a [Response] using, in order: a custom
  /// [onError] handler, [HttpError]'s own mapping, then a generic `500`.
  Future<Response> _resolveError(
    Request? req,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (_errorHandler != null && req != null) {
      try {
        return await _errorHandler!(req, error, stackTrace);
      } catch (_) {
        // A throwing error handler falls through to the defaults below.
      }
    }
    if (error is HttpError) {
      return Response.json(error.toJson(), status: error.statusCode);
    }
    stderr.writeln('Unhandled error: $error\n$stackTrace');
    return Response.json(
      {'error': 'Internal Server Error', 'statusCode': 500},
      status: 500,
    );
  }
}
