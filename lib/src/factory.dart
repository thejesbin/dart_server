import 'controller.dart';
import 'di_container.dart';
import 'module.dart';
import 'server.dart';

/// Bootstraps a [DartServer] from a root [Module], NestJS-style.
///
/// It builds the module graph, wires dependency injection (with per-module
/// encapsulation), instantiates providers and controllers, runs any [OnInit]
/// hooks, and mounts every controller's routes under its `basePath`.
///
/// ```dart
/// Future<void> main() async {
///   final app = await DartServerFactory.create(appModule());
///   app.use(logger());
///   await app.listen(3000);
/// }
/// ```
class DartServerFactory {
  DartServerFactory._();

  /// Creates and configures a [DartServer] from [rootModule].
  ///
  /// [maxBodyBytes] is forwarded to the [DartServer] constructor.
  static Future<DartServer> create(
    Module rootModule, {
    int maxBodyBytes = 1024 * 1024,
  }) async {
    final container = ModuleContainer(rootModule);
    final controllers = await container.bootstrap();

    final app = DartServer(maxBodyBytes: maxBodyBytes);
    for (final controller in controllers) {
      final registrar = RouteRegistrar();
      controller.register(registrar);
      for (final entry in registrar.entries) {
        app.route(
          entry.method,
          joinPaths(controller.basePath, entry.path),
          entry.handler,
        );
      }
    }
    return app;
  }

  /// Joins a controller [base] path with a route [path], collapsing slashes.
  ///
  /// `('/users', '/:id') -> '/users/:id'`, `('', '/health') -> '/health'`,
  /// `('/users', '/') -> '/users'`.
  static String joinPaths(String base, String path) {
    final left = base.trim();
    final right = path.trim();
    final trimmedLeft =
        (left.endsWith('/') && left.length > 1) ? left.substring(0, left.length - 1) : left;
    final hasRight = right.isNotEmpty && right != '/';
    final normalizedRight =
        hasRight ? (right.startsWith('/') ? right : '/$right') : '';
    final joined = '$trimmedLeft$normalizedRight';
    if (joined.isEmpty) return '/';
    return joined.startsWith('/') ? joined : '/$joined';
  }
}
