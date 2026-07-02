import 'dart:async';

import 'request.dart';

/// A guard decides whether a request may proceed — the single yes/no
/// checkpoint for authentication, authorization, rate limiting and the like.
///
/// Return `true` to allow the request. Returning `false` rejects it with
/// `403 Forbidden`; to reject with a different status, throw an `HttpError`
/// yourself (e.g. `HttpError.unauthorized()`).
///
/// Guards run after any middleware and before interceptors and the handler.
/// They can be attached at three levels, executed in this order:
///
/// 1. globally — `DartServerFactory.create(root, guards: [...])`
/// 2. per controller — override [Controller.guards]
/// 3. per route — `routes.get('/', handler, guards: [...])`
///
/// ```dart
/// class ApiKeyGuard implements Guard {
///   @override
///   bool canActivate(Request req) => req.headers['x-api-key'] == 'secret';
/// }
///
/// // Or inline, for one-offs:
/// final authed = Guard.from((req) => req.context['user'] != null);
/// ```
///
/// Use `req.context` to pass what a guard learns (e.g. the authenticated user)
/// on to interceptors and the handler.
///
/// Note: the request body is buffered (up to `DartServer.maxBodyBytes`)
/// before routing, so a guard rejection does not avoid the body-read cost —
/// `maxBodyBytes` is the protection against oversized uploads.
abstract interface class Guard {
  /// Whether the request may proceed.
  FutureOr<bool> canActivate(Request req);

  /// Creates a [Guard] from a function — convenient for inline, one-off
  /// guards.
  factory Guard.from(FutureOr<bool> Function(Request req) canActivate) =
      _FunctionGuard;
}

class _FunctionGuard implements Guard {
  _FunctionGuard(this._canActivate);

  final FutureOr<bool> Function(Request req) _canActivate;

  @override
  FutureOr<bool> canActivate(Request req) => _canActivate(req);
}
