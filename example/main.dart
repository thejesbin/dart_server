import 'package:dart_server/dart_server.dart';

import 'app_module.dart';

/// Entry point for the example app.
///
/// This is a complete, runnable tour of the modular architecture: a
/// provider/service injected into a controller, grouped into a feature
/// module, protected by a guard, and bootstrapped by [DartServerFactory].
///
/// The folder layout mirrors what `dart_server create` + `make:resource`
/// generate:
///
///   example/
///   ├── main.dart                     this file
///   ├── app_module.dart               root module
///   ├── app_controller.dart           root controller (/ and /health)
///   └── modules/
///       └── users/
///           ├── users_module.dart     wires the feature
///           ├── users_controller.dart routes under /users
///           ├── users_service.dart    provider (data + logic, OnInit/OnShutdown)
///           └── api_key_guard.dart    guard protecting POST /users
///
/// Run it:
///
/// ```sh
/// dart run example/main.dart
/// ```
///
/// Then try:
///
/// ```sh
/// curl localhost:4000/
/// curl localhost:4000/users
/// curl localhost:4000/users/1
/// curl localhost:4000/users/999            # -> 404 (not found)
/// curl localhost:4000/users/abc            # -> 400 (paramInt rejects it)
///
/// # POST is guarded: without the API key it's 401, with it 201.
/// curl -X POST localhost:4000/users -d '{"name":"Grace Hopper"}' \
///   -H 'Content-Type: application/json'
/// curl -X POST localhost:4000/users -d '{"name":"Grace Hopper"}' \
///   -H 'Content-Type: application/json' -H 'x-api-key: dev-secret'
/// ```
///
/// Interactive API docs are at http://localhost:4000/docs, the dev dashboard
/// at http://localhost:4000/__dev — and Ctrl-C triggers the OnShutdown hooks
/// (watch for the "[users] store closed" line).
void main() async {
  // DartServerFactory walks the module graph starting from appModule() and:
  //   1. resolves the dependency graph and instantiates every provider,
  //   2. runs OnInit hooks (here, UsersService seeds its data),
  //   3. builds the controllers and mounts their routes with the full
  //      pipeline (middleware -> guards -> interceptors -> handler).
  final app = await DartServerFactory.create(appModule());

  // The factory returns an ordinary DartServer, so the manual API still works —
  // attach middleware, the dev dashboard, or extra routes just like normal.
  app.useDevTools(); // development-only dashboard at /__dev
  // Interactive docs at /docs. Declaring the security scheme gives Swagger UI
  // an Authorize button: click it, enter dev-secret, and try-it-out requests
  // will send the x-api-key header (see ApiKeyGuard).
  app.useOpenApi(
    title: 'Users API',
    version: '1.0.0',
    securitySchemes: {
      'apiKey': ApiSecurityScheme.apiKey('x-api-key',
          description: "Use 'dev-secret' for this demo."),
    },
  );
  app.use(logger()); // logs each request, e.g. "GET /users 200 1ms"
  app.use(cors()); // permissive CORS, fine for local development

  // Run OnShutdown hooks (UsersService.onShutdown) on Ctrl-C / SIGTERM.
  app.enableShutdownHooks();

  // Start accepting connections.
  await app.listen(4000);
}
