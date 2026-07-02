import 'package:dart_server/dart_server.dart';

/// A guard — a yes/no checkpoint that decides whether a request may proceed.
///
/// Guards run after middleware and before interceptors/handlers. Returning
/// `false` rejects the request with `403 Forbidden`; throwing an [HttpError]
/// rejects with a custom status instead.
///
/// This one protects write routes: see [UsersController], which attaches it to
/// `POST /users` with `guards: [ApiKeyGuard()]`.
class ApiKeyGuard implements Guard {
  /// Hard-coded for the demo — read it from `Env` in a real app.
  static const _apiKey = 'dev-secret';

  @override
  bool canActivate(Request req) {
    // Missing key -> 401 rather than the default 403.
    final provided = req.headers['x-api-key'];
    if (provided == null) {
      throw HttpError.unauthorized('Provide an x-api-key header');
    }
    return provided == _apiKey;
  }
}
