import 'package:dart_server/dart_server.dart';

/// A small but complete API showing off routing, route params, JSON parsing,
/// middleware, error handling and the bundled CORS / logging middleware.
///
/// Run it with:
///
/// ```sh
/// dart run example/main.dart
/// ```
///
/// Then try:
///
/// ```sh
/// curl localhost:3000/
/// curl localhost:3000/users/42
/// curl localhost:3000/search?q=dart
/// curl -X POST localhost:3000/login -d '{"email":"a@b.com"}' \
///   -H 'Content-Type: application/json'
/// curl -X POST localhost:3000/users -d '{"name":"Ada"}' \
///   -H 'Content-Type: application/json'
/// curl localhost:3000/boom
/// ```
void main() async {
  final app = DartServer();

  // --- Dev tools -------------------------------------------------------------

  // Mounts a request-tracking dashboard at http://localhost:3000/__dev
  // Active only in development (no-op in a compiled production build).
  app.useDevTools();

  // --- Global middleware -----------------------------------------------------

  // Log every request: "GET /users/42 200 1ms".
  app.use(logger());

  // Allow cross-origin requests (wide open — tighten `origin` in production).
  app.use(cors());

  // A custom inline middleware that stamps a request id onto the context.
  app.use((req, next) async {
    req.context['requestId'] = '${req.method}:${req.path}';
    return await next();
  });

  // --- Routes ----------------------------------------------------------------

  app.get('/', (req) => Response.text('Hello World'));

  // Route parameters are available via `req.params`.
  app.get('/users/:id', (req) {
    return Response.json({'id': req.params['id']});
  });

  // Query parameters are parsed into `req.query`.
  app.get('/search', (req) {
    return Response.json({'query': req.query['q'], 'results': []});
  });

  // Parse a JSON body with `req.json()`.
  app.post('/login', (req) async {
    final body = await req.json() as Map<String, dynamic>?;
    final email = body?['email'];
    if (email == null) {
      throw HttpError.badRequest('email is required');
    }
    return Response.json({'token': 'abc', 'email': email});
  });

  app.post('/users', (req) async {
    final body = await req.json() as Map<String, dynamic>?;
    return Response.status(201, {'id': 1, 'name': body?['name']});
  });

  app.put('/users/:id', (req) async {
    final body = await req.json();
    return Response.json({'id': req.params['id'], 'updated': body});
  });

  app.delete('/users/:id', (req) {
    return Response.status(204);
  });

  // Throwing inside a handler is caught and turned into a JSON error response.
  app.get('/boom', (req) {
    throw StateError('something went wrong');
  });

  // --- Error handling --------------------------------------------------------

  // Optional: customize how uncaught errors become responses.
  app.onError((req, error, stackTrace) {
    if (error is HttpError) {
      return Response.json(error.toJson(), status: error.statusCode);
    }
    return Response.json(
      {'error': 'Unexpected error', 'path': req.path},
      status: 500,
    );
  });

  await app.listen(3000);
  // ignore: avoid_print
  print('Dev dashboard: http://localhost:3000/__dev');
}
