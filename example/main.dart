import 'package:dart_server/dart_server.dart';

import 'app_module.dart';

/// Entry point for the example app.
///
/// This is a complete, runnable tour of the modular (NestJS-style)
/// architecture: a provider/service injected into a controller, grouped into a
/// feature module, imported by a root module, and bootstrapped by
/// [DartServerFactory].
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
///           └── users_service.dart    provider (data + logic)
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
/// curl localhost:3000/
/// curl localhost:3000/users
/// curl localhost:3000/users/1
/// curl localhost:3000/users/999            # -> 404
/// curl -X POST localhost:3000/users -d '{"name":"Grace Hopper"}' \
///   -H 'Content-Type: application/json'
/// ```
///
/// The dev dashboard is at http://localhost:3000/__dev
void main() async {
  // DartServerFactory walks the module graph starting from appModule() and:
  //   1. resolves the dependency graph and instantiates every provider,
  //   2. runs OnInit hooks (here, UsersService seeds its data),
  //   3. builds the controllers and mounts their routes.
  // It returns a ready-to-serve DartServer.
  final app = await DartServerFactory.create(appModule());

  // The factory returns an ordinary DartServer, so the manual API still works —
  // attach middleware, the dev dashboard, or extra routes just like normal.
  app.useDevTools(); // development-only dashboard at /__dev
  app.use(logger()); // logs each request, e.g. "GET /users 200 1ms"
  app.use(cors()); // permissive CORS, fine for local development

  // Start accepting connections on port 3000.
  await app.listen(3000);
}
