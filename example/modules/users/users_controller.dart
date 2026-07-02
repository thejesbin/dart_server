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

  /// The user payload shape, shared by the OpenAPI docs below.
  static final _userSchema = ApiSchema.object(
    properties: {
      'id': ApiSchema.integer(example: 1),
      'name': ApiSchema.string(example: 'Ada Lovelace'),
    },
    required: ['id', 'name'],
  );

  /// Declares the routes; paths here are relative to [basePath].
  ///
  /// Routes can attach guards, interceptors, middleware, exception filters —
  /// and `doc:` metadata that enriches the generated OpenAPI docs at `/docs`.
  /// Here the write route is protected by [ApiKeyGuard] while reads stay
  /// public.
  @override
  void register(RouteRegistrar routes) {
    routes.get('/', index,
        doc: ApiDoc(
          summary: 'List all users',
          responses: {200: ApiResponse('Every user in the store')},
        ));
    routes.get('/:id', show,
        doc: ApiDoc(
          summary: 'Fetch one user',
          params: {'id': ApiParam(description: 'The user id', example: 1)},
          responses: {
            200: ApiResponse('The user', schema: _userSchema),
            404: ApiResponse('No user with that id'),
          },
        ));
    routes.post('/', store,
        guards: [ApiKeyGuard()],
        doc: ApiDoc(
          summary: 'Create a user',
          description: 'Requires the `x-api-key` header (see ApiKeyGuard).',
          // References the scheme declared in useOpenApi — Swagger UI shows a
          // lock icon and sends the key from its Authorize dialog.
          security: ['apiKey'],
          body: ApiBody(
            schema: ApiSchema.object(
              properties: {'name': ApiSchema.string(example: 'Grace Hopper')},
              required: ['name'],
            ),
          ),
          responses: {
            201: ApiResponse('The created user', schema: _userSchema),
            400: ApiResponse('Missing or empty name'),
            401: ApiResponse('Missing x-api-key header'),
          },
        ));
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
