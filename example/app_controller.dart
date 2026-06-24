import 'package:dart_server/dart_server.dart';

/// The application's root controller.
///
/// It declares no [basePath], so its routes are mounted at the top level (`/`).
/// Use a controller like this for app-wide endpoints that don't belong to a
/// particular feature module (health checks, a landing route, etc.).
class AppController extends Controller {
  /// Declares the routes this controller handles. [RouteRegistrar] mirrors the
  /// `app.get/post/...` API you'd use on a plain [DartServer].
  @override
  void register(RouteRegistrar routes) {
    // A plain-text response.
    routes.get('/', (req) => Response.text('Hello from dart_server'));
    // A JSON health check.
    routes.get('/health', (req) => Response.json({'status': 'ok'}));
  }
}
