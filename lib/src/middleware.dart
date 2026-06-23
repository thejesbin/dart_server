import 'dart:async';
import 'dart:io';

import 'request.dart';
import 'response.dart';
import 'utils.dart';

/// A route handler.
///
/// Receives the incoming [Request] and returns a [Response] (or a `Future`
/// that completes with one). Returning synchronously is allowed:
///
/// ```dart
/// app.get('/', (req) => Response.text('Hello'));
/// app.post('/login', (req) async => Response.json(await authenticate(req)));
/// ```
typedef Handler = FutureOr<Response> Function(Request req);

/// The continuation passed to a [Middleware].
///
/// Calling it runs the next middleware in the chain (and ultimately the matched
/// route handler) and returns its [Response]. Not calling it short-circuits the
/// chain — useful for auth guards, caching layers, etc.
typedef Next = FutureOr<Response> Function();

/// A piece of middleware.
///
/// Middleware wraps the request lifecycle: it can inspect or mutate the
/// [Request], decide whether to continue by calling [next], and inspect or
/// mutate the [Response] on the way back out.
///
/// ```dart
/// app.use((req, next) async {
///   final started = DateTime.now();
///   final res = await next();           // run the rest of the chain
///   print('${req.method} ${req.path} -> ${res.statusCode}');
///   return res;
/// });
/// ```
typedef Middleware = FutureOr<Response> Function(Request req, Next next);

/// Handles uncaught errors thrown anywhere in the middleware/route chain and
/// turns them into a [Response].
typedef ErrorHandler = FutureOr<Response> Function(
  Request req,
  Object error,
  StackTrace stackTrace,
);

/// A request/response logging middleware.
///
/// Logs one line per request with the method, path, status code and the time
/// taken to produce the response — including error responses (a handler that
/// throws is logged with its resolved status, e.g. `500`):
///
/// ```
/// GET /users/42 200 3ms
/// ```
///
/// * [log] receives each formatted line (defaults to `stdout.writeln`).
/// * Set [includeTimestamp] to prefix each line with an ISO-8601 timestamp.
Middleware logger({
  void Function(String line)? log,
  bool includeTimestamp = false,
}) {
  final write = log ?? stdout.writeln;
  return (req, next) async {
    final stopwatch = Stopwatch()..start();
    Response res;
    try {
      res = await next();
    } finally {
      stopwatch.stop();
    }
    final prefix = includeTimestamp ? '${DateTime.now().toIso8601String()} ' : '';
    write('$prefix${req.method} ${req.path} '
        '${res.statusCode} ${stopwatch.elapsedMilliseconds}ms');
    return res;
  };
}

/// A CORS (Cross-Origin Resource Sharing) middleware.
///
/// Adds the appropriate `Access-Control-*` headers to responses (including
/// error responses, since errors flow back through the chain) and answers
/// browser pre-flight requests with `204 No Content`.
///
/// ```dart
/// app.use(cors());                                   // wide-open, good for dev
/// app.use(cors(origin: 'https://app.example.com'));  // single fixed origin
/// app.use(cors(                                      // credentialed allow-list
///   origins: ['https://app.example.com', 'https://admin.example.com'],
///   credentials: true,
/// ));
/// ```
///
/// Security: combining [credentials] `true` with the default wildcard
/// [origin] (`*`) is forbidden and throws [ArgumentError], because reflecting an
/// arbitrary `Origin` alongside `Access-Control-Allow-Credentials: true` lets
/// any site read authenticated responses. Use [origins] (an allow-list) for
/// credentialed cross-origin access — the request's `Origin` is echoed only
/// when it is a member, and omitted otherwise.
///
/// A pre-flight is detected by the presence of the `Access-Control-Request-Method`
/// header, so genuine `OPTIONS` routes you register with `app.options(...)`
/// still run.
Middleware cors({
  String origin = '*',
  List<String>? origins,
  List<String> methods = const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  List<String> allowedHeaders = const ['Content-Type', 'Authorization'],
  List<String> exposedHeaders = const [],
  bool credentials = false,
  int maxAge = 86400,
}) {
  if (credentials && origins == null && origin == '*') {
    throw ArgumentError(
      "cors: credentials:true cannot be combined with a wildcard origin ('*'). "
      'Pass a specific `origin:` or an `origins:` allow-list instead.',
    );
  }

  final methodsValue = methods.join(', ');
  final allowedHeadersValue = allowedHeaders.join(', ');
  final exposedHeadersValue = exposedHeaders.join(', ');
  final allowList = origins?.toSet();

  /// The `Access-Control-Allow-Origin` value to send, or `null` to omit it
  /// (which causes the browser to block the cross-origin read).
  String? resolveOrigin(Request req) {
    if (allowList != null) {
      final requestOrigin = req.headers['origin'];
      return (requestOrigin != null && allowList.contains(requestOrigin))
          ? requestOrigin
          : null;
    }
    return origin;
  }

  Map<String, String> headersFor(Request req) {
    final allowOrigin = resolveOrigin(req);
    return {
      if (allowOrigin != null) 'Access-Control-Allow-Origin': allowOrigin,
      'Access-Control-Allow-Methods': methodsValue,
      'Access-Control-Allow-Headers': allowedHeadersValue,
      if (exposedHeadersValue.isNotEmpty)
        'Access-Control-Expose-Headers': exposedHeadersValue,
      if (credentials) 'Access-Control-Allow-Credentials': 'true',
      // Responses vary by Origin whenever the value is request-dependent.
      if (allowList != null) 'Vary': 'Origin',
    };
  }

  return (req, next) async {
    final isPreflight = req.method == 'OPTIONS' &&
        req.headers.containsKey('access-control-request-method');
    if (isPreflight) {
      return Response.bytes(
        const [],
        status: 204,
        headers: {
          ...headersFor(req),
          'Access-Control-Max-Age': '$maxAge',
        },
      );
    }
    final res = await next();
    headersFor(req).forEach((key, value) {
      res.headers.putIfAbsent(key, () => value);
    });
    return res;
  };
}

/// A static-file serving middleware.
///
/// Serves files from the [root] directory on disk. If the request doesn't map
/// to an existing file the chain continues via `next()`, so you can mount it
/// alongside your API routes.
///
/// ```dart
/// app.use(serveStatic('public'));              // serve ./public at /
/// app.use(serveStatic('build', urlPrefix: '/app'));
/// ```
///
/// * [urlPrefix] strips a leading path prefix before resolving on disk.
/// * [indexFile] is served for directory requests (e.g. `/` -> `/index.html`).
/// * Path traversal (`..`) outside [root] is rejected with `403 Forbidden` —
///   including via symlinks, whose real target is re-checked against the root.
Middleware serveStatic(
  String root, {
  String urlPrefix = '/',
  String indexFile = 'index.html',
}) {
  final rootDir = Directory(root).absolute;
  final rootPath = normalizeFilePath(rootDir.path);

  return (req, next) async {
    if (req.method != 'GET' && req.method != 'HEAD') return next();

    var relativePath = req.path;
    if (urlPrefix != '/' && urlPrefix.isNotEmpty) {
      if (!relativePath.startsWith(urlPrefix)) return next();
      relativePath = relativePath.substring(urlPrefix.length);
    }
    // A malformed percent-escape isn't a file we can serve — fall through.
    try {
      relativePath = Uri.decodeComponent(relativePath);
    } catch (_) {
      return next();
    }
    if (relativePath.isEmpty || relativePath == '/') {
      relativePath = '/$indexFile';
    }

    final resolved = normalizeFilePath('$rootPath/$relativePath');
    // Lexical guard against `..` traversal outside of the configured root.
    if (resolved != rootPath && !resolved.startsWith('$rootPath/')) {
      return Response.json({'error': 'Forbidden'}, status: 403);
    }

    var file = File(resolved);
    if (await FileSystemEntity.isDirectory(resolved)) {
      file = File('$resolved/$indexFile');
    }
    if (!await file.exists()) return next();

    // Re-check the *real* (symlink-resolved) path so a symlink inside the root
    // can't point the request at a file outside it. resolveSymbolicLinks also
    // canonicalizes the root (e.g. macOS /tmp -> /private/tmp), so compare both.
    try {
      final realFile = normalizeFilePath(await file.resolveSymbolicLinks());
      final realRoot = normalizeFilePath(await rootDir.resolveSymbolicLinks());
      if (realFile != realRoot && !realFile.startsWith('$realRoot/')) {
        return Response.json({'error': 'Forbidden'}, status: 403);
      }
    } on FileSystemException {
      return next();
    }

    final bytes = await file.readAsBytes();
    return Response.bytes(
      bytes,
      contentType: ContentType.parse(mimeTypeForPath(file.path)),
    );
  };
}
