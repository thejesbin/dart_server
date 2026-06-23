import 'middleware.dart';
import 'utils.dart';

/// A single registered route: an HTTP [method], a path [pattern] and the
/// [handler] to run when both match.
///
/// Patterns may contain named parameters prefixed with `:` (e.g.
/// `/users/:id/posts/:postId`) and a single trailing wildcard `*` that matches
/// the remainder of the path. A `*` anywhere other than the final segment is
/// rejected at registration time.
class Route {
  /// The matched HTTP method in upper case, or `ALL` to match any method.
  final String method;

  /// The original path pattern as registered, e.g. `/users/:id`.
  final String pattern;

  /// The handler invoked on a successful match.
  final Handler handler;

  /// The pattern split into segments, computed once at registration time.
  final List<String> segments;

  Route(String method, this.pattern, this.handler)
      : method = method.toUpperCase(),
        segments = splitPath(pattern) {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] == '*' && i != segments.length - 1) {
        throw ArgumentError.value(pattern, 'pattern',
            'A wildcard "*" may only appear as the final path segment');
      }
    }
  }
}

/// The result of matching a request against the route table: the [handler] to
/// run and the extracted path [params].
class RouteMatch {
  /// The handler whose route matched.
  final Handler handler;

  /// Named path parameters, e.g. `{'id': '42'}` for `/users/:id`.
  final Map<String, String> params;

  RouteMatch(this.handler, this.params);
}

/// The routing table.
///
/// Routes are matched in registration order, so more specific routes should be
/// registered before more general ones.
class Router {
  final List<Route> _routes = [];

  /// Registers [handler] for [method] requests to [path].
  void add(String method, String path, Handler handler) {
    _routes.add(Route(method, path, handler));
  }

  /// The registered routes as `(method, pattern)` records, in registration
  /// order. Used by the dev dashboard to list the route table.
  List<({String method, String pattern})> get registeredRoutes =>
      _routes.map((r) => (method: r.method, pattern: r.pattern)).toList();

  /// Finds the first route matching [method] and [path], or `null` if none do.
  ///
  /// A `HEAD` request with no explicit `HEAD` route falls back to the matching
  /// `GET` handler (the body is suppressed when the response is written), which
  /// is the conventional Express-style behavior.
  RouteMatch? match(String method, String path) {
    final requestMethod = method.toUpperCase();
    final direct = _matchMethod(requestMethod, path);
    if (direct != null) return direct;
    if (requestMethod == 'HEAD') return _matchMethod('GET', path);
    return null;
  }

  RouteMatch? _matchMethod(String requestMethod, String path) {
    final requestSegments = splitPath(path);
    for (final route in _routes) {
      if (route.method != 'ALL' && route.method != requestMethod) continue;
      final params = _matchSegments(route.segments, requestSegments);
      if (params != null) return RouteMatch(route.handler, params);
    }
    return null;
  }

  /// The set of HTTP methods registered for [path], regardless of the request
  /// method. Used to answer with `405 Method Not Allowed` (and an `Allow`
  /// header) instead of `404` when a path exists but the method doesn't.
  Set<String> allowedMethods(String path) {
    final requestSegments = splitPath(path);
    final methods = <String>{};
    for (final route in _routes) {
      if (_matchSegments(route.segments, requestSegments) != null) {
        methods.add(route.method);
      }
    }
    return methods;
  }

  /// Attempts to match [pattern] segments against [actual] segments, returning
  /// the extracted parameters on success or `null` on failure.
  Map<String, String>? _matchSegments(
    List<String> pattern,
    List<String> actual,
  ) {
    final params = <String, String>{};
    for (var i = 0; i < pattern.length; i++) {
      final patternSegment = pattern[i];

      // Trailing wildcard captures everything that remains. (Route's
      // constructor guarantees `*` is only ever the final segment.)
      if (patternSegment == '*') {
        params['*'] = actual.skip(i).map(_decode).join('/');
        return params;
      }

      // Ran out of request segments to match against.
      if (i >= actual.length) return null;

      if (patternSegment.startsWith(':')) {
        params[patternSegment.substring(1)] = _decode(actual[i]);
      } else if (patternSegment != actual[i]) {
        return null;
      }
    }
    // Both must be fully consumed for a non-wildcard match.
    return pattern.length == actual.length ? params : null;
  }

  /// Percent-decodes a path segment, falling back to the raw value when the
  /// input contains a malformed escape — so a bad client URL yields a normal
  /// match/404 rather than bubbling a `FormatException` up to a `500`.
  static String _decode(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }
}
