import 'package:dart_server/dart_server.dart';

import 'api_key_guard.dart';
import 'users_service.dart';

/// A controller — groups related routes and turns requests into responses.
///
/// Its dependencies arrive through the constructor; the module is responsible
/// for supplying them (see [usersModule]). dart_server never reaches inside a
/// controller to set fields — everything comes in via the constructor, which
/// keeps the wiring explicit and the controller easy to test.
class UsersController extends Controller {
  UsersController(this._users);

  // Injected by the module via `i.get<UsersService>()`.
  final UsersService _users;

  /// Every route below is mounted under this prefix, so `'/'` becomes `/users`
  /// and `'/:id'` becomes `/users/:id`.
  @override
  String get basePath => '/users';

  /// Declares the routes; paths here are relative to [basePath].
  ///
  /// Routes can attach guards, interceptors, middleware and exception filters
  /// — here the write route is protected by [ApiKeyGuard] while reads stay
  /// public.
  @override
  void register(RouteRegistrar routes) {
    routes.get('/', index);
    routes.get('/:id', show);
    routes.post('/', store, guards: [ApiKeyGuard()]);
  }

  /// `GET /users` — list every user.
  Response index(Request req) => Response.json({'data': _users.all()});

  /// `GET /users/:id` — fetch one user, or 404 if it doesn't exist.
  Response show(Request req) {
    // paramInt is the ParseIntPipe equivalent: /users/abc -> 400, not a 500.
    final id = req.paramInt('id');
    final user = _users.find(id);
    // A thrown HttpError is turned into a JSON error response automatically.
    if (user == null) throw HttpError.notFound('User $id not found');
    return Response.json(user);
  }

  /// `POST /users` — create a user from the JSON request body.
  /// Guarded by [ApiKeyGuard]: requires the `x-api-key: dev-secret` header.
  Future<Response> store(Request req) async {
    // jsonMap() validates the body is a JSON object (else 400 Bad Request).
    final body = await req.jsonMap();
    final name = body['name'] as String?;
    if (name == null || name.isEmpty) {
      throw HttpError.badRequest('name is required');
    }
    // Response.status(201, ...) sets the status code and JSON-encodes the body.
    return Response.status(201, _users.create(name));
  }
}
