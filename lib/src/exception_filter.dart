import 'dart:async';

import 'request.dart';
import 'response.dart';

/// Converts an error thrown by a route's guards, interceptors or handler into
/// a [Response] — the last stop between a thrown error and the client, letting
/// you shape error responses per route, per controller or app-wide.
///
/// Return a [Response] to handle the error, or `null` to decline and let the
/// next filter try. Filters run most-specific-first — route, then controller,
/// then global — and an error no filter handles falls through to the
/// framework's built-in mapping (`onError`, `HttpError` → status, else `500`).
///
/// A filter selects the errors it wants with a plain `is` check and returns
/// `null` for the rest:
///
/// ```dart
/// class TimeoutFilter implements ExceptionFilter {
///   @override
///   Response? handle(Request req, Object error, StackTrace stackTrace) {
///     if (error is TimeoutException) {
///       return Response.json({'error': 'Upstream timed out'}, status: 504);
///     }
///     return null; // not ours — let the next filter (or the default) handle it
///   }
/// }
/// ```
///
/// Attach filters per route (`routes.get('/', handler, filters: [...])`), per
/// controller ([Controller.filters]) or globally
/// (`DartServerFactory.create(root, filters: [...])`).
///
/// Note: filters wrap guards, interceptors and the handler — not scoped
/// middleware. An error thrown by controller/route middleware itself skips the
/// filters and goes straight to the built-in mapping.
abstract interface class ExceptionFilter {
  /// Handles [error], returning a [Response] or `null` to decline.
  FutureOr<Response?> handle(Request req, Object error, StackTrace stackTrace);

  /// Creates an [ExceptionFilter] from a function — convenient for inline
  /// filters.
  factory ExceptionFilter.from(
    FutureOr<Response?> Function(
            Request req, Object error, StackTrace stackTrace)
        handle,
  ) = _FunctionExceptionFilter;
}

class _FunctionExceptionFilter implements ExceptionFilter {
  _FunctionExceptionFilter(this._handle);

  final FutureOr<Response?> Function(
      Request req, Object error, StackTrace stackTrace) _handle;

  @override
  FutureOr<Response?> handle(
          Request req, Object error, StackTrace stackTrace) =>
      _handle(req, error, stackTrace);
}
