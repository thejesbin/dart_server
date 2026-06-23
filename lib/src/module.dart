import 'controller.dart';

/// Resolves dependencies for a [Provider] factory or [Controller], scoped to
/// the module it belongs to (so it only sees that module's own providers plus
/// the providers exported by the modules it imports).
abstract class Injector {
  /// Returns the instance registered for type [T], or throws [DiError] if no
  /// such provider is visible to the current module.
  T get<T extends Object>();
}

/// How often a [Provider]'s instance is created.
enum ProviderScope {
  /// One shared instance for the whole application (the default).
  singleton,

  /// A new instance every time it is resolved.
  transient,

  /// A pre-built value supplied directly.
  value,
}

/// A dependency-injection registration: how to create the instance for a type
/// (its "token").
///
/// ```dart
/// Provider.singleton((i) => UsersService(i.get<Database>()));
/// Provider.value<Config>(Config.fromEnv());
/// Provider.transient((i) => RequestId());
/// ```
class Provider {
  Provider._(this.token, this.scope, this._factory);

  /// The type this provider satisfies (used as the lookup key).
  final Type token;

  /// This provider's [ProviderScope].
  final ProviderScope scope;

  final Object Function(Injector injector) _factory;

  /// Creates the instance using [injector] to resolve its dependencies.
  Object create(Injector injector) => _factory(injector);

  /// A single shared instance, created lazily the first time it is needed.
  static Provider singleton<T extends Object>(
          T Function(Injector injector) create) =>
      Provider._(T, ProviderScope.singleton, (i) => create(i));

  /// A fresh instance every time it is resolved.
  static Provider transient<T extends Object>(
          T Function(Injector injector) create) =>
      Provider._(T, ProviderScope.transient, (i) => create(i));

  /// A pre-built [instance].
  static Provider value<T extends Object>(T instance) =>
      Provider._(T, ProviderScope.value, (_) => instance);
}

/// Builds a [Controller] from an [Injector], resolving its dependencies.
typedef ControllerFactory = Controller Function(Injector injector);

/// A unit of an application: a cohesive group of [providers] (services) and
/// [controllers], plus the other modules it [imports] and the provider types it
/// [exports] for importers to use.
///
/// Providers are encapsulated: a module can only inject providers it declares
/// itself or that an imported module exports. Mark a module [isGlobal] to make
/// its exports visible everywhere.
///
/// ```dart
/// Module usersModule() => Module(
///   providers: [Provider.singleton((i) => UsersService())],
///   controllers: [(i) => UsersController(i.get<UsersService>())],
///   exports: [UsersService],
/// );
///
/// Module appModule() => Module(
///   imports: [usersModule()],
///   controllers: [(i) => AppController()],
/// );
/// ```
class Module {
  Module({
    this.imports = const [],
    this.providers = const [],
    this.controllers = const [],
    this.exports = const [],
    this.isGlobal = false,
  });

  /// Other modules this module depends on; their exported providers become
  /// visible here.
  final List<Module> imports;

  /// Services and values provided (and owned) by this module.
  final List<Provider> providers;

  /// Controllers whose routes this module contributes.
  final List<ControllerFactory> controllers;

  /// The provider types this module makes available to modules that import it.
  final List<Type> exports;

  /// When `true`, this module's [exports] are visible to every module without
  /// needing to import it.
  final bool isGlobal;
}

/// A dependency-injection / module-wiring error, thrown during bootstrap for
/// missing providers, circular dependencies and invalid exports.
class DiError extends Error {
  DiError(this.message);

  /// Human-readable description of what went wrong.
  final String message;

  @override
  String toString() => 'DiError: $message';
}

/// Optional lifecycle hook: any provider or controller implementing this has
/// [onInit] awaited once during bootstrap, after the whole graph is wired (in
/// dependency order).
abstract class OnInit {
  /// Runs one-time async initialization (e.g. opening a DB connection).
  Future<void> onInit();
}
